//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftAWSLambdaRuntime open source project
//
// Copyright SwiftAWSLambdaRuntime project authors
// Copyright (c) Amazon.com, Inc. or its affiliates.
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftAWSLambdaRuntime project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Logging
import NIOCore
import NIOHTTP1
import NIOPosix

internal protocol LambdaChannelHandlerDelegate {
    func connectionWillClose(channel: any Channel)
    func connectionErrorHappened(_ error: any Error, channel: any Channel)
}

@available(LambdaSwift 2.0, *)
internal final class LambdaChannelHandler<Delegate: LambdaChannelHandlerDelegate> {
    let nextInvocationPath = Consts.invocationURLPrefix + Consts.getNextInvocationURLSuffix

    enum State {
        case disconnected
        case connected(ChannelHandlerContext, LambdaState)
        case closing

        enum LambdaState {
            /// this is the "normal" state. Transitions to `waitingForNextInvocation`
            case idle
            /// this is the state while we wait for an invocation. A next call is running.
            /// Transitions to `waitingForResponse`
            case waitingForNextInvocation(CheckedContinuation<Invocation, any Error>)
            /// The invocation was forwarded to the handler and we wait for a response.
            /// Transitions to `sendingResponse` or `sentResponse`.
            case waitingForResponse
            case sendingResponse
            case sentResponse(CheckedContinuation<Void, any Error>)
        }
    }

    private var state: State = .disconnected
    private var lastError: Error?
    private var reusableErrorBuffer: ByteBuffer?
    private let logger: Logger
    private let delegate: Delegate
    private let configuration: LambdaRuntimeClient.Configuration

    /// These are the default headers that must be sent along an invocation
    let defaultHeaders: HTTPHeaders
    /// These headers must be sent along an invocation or initialization error report
    let errorHeaders: HTTPHeaders
    /// These headers must be sent when streaming a large response
    let largeResponseHeaders: HTTPHeaders
    /// These headers must be sent when the handler streams its response
    let streamingHeaders: HTTPHeaders

    init(
        delegate: Delegate,
        logger: Logger,
        configuration: LambdaRuntimeClient.Configuration
    ) {
        self.delegate = delegate
        self.logger = logger
        self.configuration = configuration
        self.defaultHeaders = [
            "host": "\(self.configuration.ip):\(self.configuration.port)",
            "user-agent": .userAgent,
        ]
        self.errorHeaders = [
            "host": "\(self.configuration.ip):\(self.configuration.port)",
            "user-agent": .userAgent,
            "lambda-runtime-function-error-type": "Unhandled",
        ]
        self.largeResponseHeaders = [
            "host": "\(self.configuration.ip):\(self.configuration.port)",
            "user-agent": .userAgent,
            "transfer-encoding": "chunked",
        ]
        // https://docs.aws.amazon.com/lambda/latest/dg/runtimes-custom.html#runtimes-custom-response-streaming
        // These are the headers returned by the Runtime to the Lambda Data plane.
        // These are not the headers the Lambda Data plane sends to the caller of the Lambda function
        // The developer of the function can set the caller's headers in the handler code.
        self.streamingHeaders = [
            "host": "\(self.configuration.ip):\(self.configuration.port)",
            "user-agent": .userAgent,
            "Lambda-Runtime-Function-Response-Mode": "streaming",
            // these are not used by this runtime client at the moment
            // FIXME: the eror handling should inject these headers in the streamed response to report mid-stream errors
            "Trailer": "Lambda-Runtime-Function-Error-Type, Lambda-Runtime-Function-Error-Body",
        ]
    }

    func nextInvocation(isolation: isolated (any Actor)? = #isolation) async throws -> Invocation {
        switch self.state {
        case .connected(let context, .idle):
            return try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Invocation, any Error>) in
                self.state = .connected(context, .waitingForNextInvocation(continuation))
                self.sendNextRequest(context: context)
            }

        case .connected(_, .sendingResponse),
            .connected(_, .sentResponse),
            .connected(_, .waitingForNextInvocation),
            .connected(_, .waitingForResponse),
            .closing:
            fatalError("Invalid state: \(self.state)")

        case .disconnected:
            throw LambdaRuntimeError(code: .connectionToControlPlaneLost)
        }
    }

    func reportError(
        isolation: isolated (any Actor)? = #isolation,
        _ error: any Error,
        requestID: String
    ) async throws {
        switch self.state {
        case .connected(_, .waitingForNextInvocation):
            fatalError("Invalid state: \(self.state)")

        case .connected(let context, .waitingForResponse):
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                self.state = .connected(context, .sentResponse(continuation))
                self.sendReportErrorRequest(requestID: requestID, error: error, context: context)
            }

        case .connected(let context, .sendingResponse):
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                self.state = .connected(context, .sentResponse(continuation))
                self.sendResponseStreamingFailure(error: error, context: context)
            }

        case .connected(_, .idle),
            .connected(_, .sentResponse):
            // The final response has already been sent. The only way to report the unhandled error
            // now is to log it. Normally this library never logs higher than debug, we make an
            // exception here, as there is no other way of reporting the error.
            self.logger.error(
                "Unhandled error after stream has finished",
                metadata: [
                    "lambda_request_id": "\(requestID)",
                    "lambda_error": "\(String(describing: error))",
                ]
            )

        case .disconnected:
            throw LambdaRuntimeError(code: .connectionToControlPlaneLost)

        case .closing:
            throw LambdaRuntimeError(code: .connectionToControlPlaneGoingAway)
        }
    }

    func writeResponseBodyPart(
        isolation: isolated (any Actor)? = #isolation,
        _ byteBuffer: ByteBuffer,
        requestID: String,
        hasCustomHeaders: Bool
    ) async throws {
        switch self.state {
        case .connected(_, .waitingForNextInvocation):
            fatalError("Invalid state: \(self.state)")

        case .connected(let context, .waitingForResponse):
            self.state = .connected(context, .sendingResponse)
            try await self.sendResponseBodyPart(
                byteBuffer,
                sendHeadWithRequestID: requestID,
                context: context,
                hasCustomHeaders: hasCustomHeaders
            )

        case .connected(let context, .sendingResponse):

            precondition(!hasCustomHeaders, "Programming error: Custom headers should not be sent in this state")

            try await self.sendResponseBodyPart(
                byteBuffer,
                sendHeadWithRequestID: nil,
                context: context,
                hasCustomHeaders: hasCustomHeaders
            )

        case .connected(_, .idle),
            .connected(_, .sentResponse):
            throw LambdaRuntimeError(code: .writeAfterFinishHasBeenSent)

        case .disconnected:
            throw LambdaRuntimeError(code: .connectionToControlPlaneLost)

        case .closing:
            throw LambdaRuntimeError(code: .connectionToControlPlaneGoingAway)
        }
    }

    func finishResponseRequest(
        isolation: isolated (any Actor)? = #isolation,
        finalData: ByteBuffer?,
        requestID: String
    ) async throws {
        switch self.state {
        case .connected(_, .idle),
            .connected(_, .waitingForNextInvocation):
            fatalError("Invalid state: \(self.state)")

        case .connected(let context, .waitingForResponse):
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                self.state = .connected(context, .sentResponse(continuation))
                self.sendResponseFinish(finalData, sendHeadWithRequestID: requestID, context: context)
            }

        case .connected(let context, .sendingResponse):
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                self.state = .connected(context, .sentResponse(continuation))
                self.sendResponseFinish(finalData, sendHeadWithRequestID: nil, context: context)
            }

        case .connected(_, .sentResponse):
            throw LambdaRuntimeError(code: .finishAfterFinishHasBeenSent)

        case .disconnected:
            throw LambdaRuntimeError(code: .connectionToControlPlaneLost)

        case .closing:
            throw LambdaRuntimeError(code: .connectionToControlPlaneGoingAway)
        }
    }

    private func sendResponseBodyPart(
        isolation: isolated (any Actor)? = #isolation,
        _ byteBuffer: ByteBuffer,
        sendHeadWithRequestID: String?,
        context: ChannelHandlerContext,
        hasCustomHeaders: Bool
    ) async throws {

        if let requestID = sendHeadWithRequestID {
            // TODO: This feels super expensive. We should be able to make this cheaper. requestIDs are fixed length.
            let url = Consts.invocationURLPrefix + "/" + requestID + Consts.postResponseURLSuffix

            var headers = self.streamingHeaders
            if hasCustomHeaders {
                // this header is required by Function URL when the user sends custom status code or headers
                headers.add(name: "Content-Type", value: "application/vnd.awslambda.http-integration-response")
            }
            let httpRequest = HTTPRequestHead(
                version: .http1_1,
                method: .POST,
                uri: url,
                headers: headers
            )

            context.write(self.wrapOutboundOut(.head(httpRequest)), promise: nil)
        }

        let future = context.write(self.wrapOutboundOut(.body(.byteBuffer(byteBuffer))))
        context.flush()
        try await future.get()
    }

    private func sendResponseFinish(
        isolation: isolated (any Actor)? = #isolation,
        _ byteBuffer: ByteBuffer?,
        sendHeadWithRequestID: String?,
        context: ChannelHandlerContext
    ) {
        if let requestID = sendHeadWithRequestID {
            // TODO: This feels quite expensive. We should be able to make this cheaper. requestIDs are fixed length.
            let url = "\(Consts.invocationURLPrefix)/\(requestID)\(Consts.postResponseURLSuffix)"

            // If we have less than 6MB, we don't want to use the streaming API. If we have more
            // than 6MB, we must use the streaming mode.
            var headers: HTTPHeaders!
            if byteBuffer?.readableBytes ?? 0 < 6_000_000 {
                headers = self.defaultHeaders
                headers.add(name: "content-length", value: "\(byteBuffer?.readableBytes ?? 0)")
            } else {
                headers = self.largeResponseHeaders
            }
            let httpRequest = HTTPRequestHead(
                version: .http1_1,
                method: .POST,
                uri: url,
                headers: headers
            )

            context.write(self.wrapOutboundOut(.head(httpRequest)), promise: nil)
        }

        if let byteBuffer {
            context.write(self.wrapOutboundOut(.body(.byteBuffer(byteBuffer))), promise: nil)
        }

        context.write(self.wrapOutboundOut(.end(nil)), promise: nil)
        context.flush()
    }

    private func sendNextRequest(context: ChannelHandlerContext) {
        let httpRequest = HTTPRequestHead(
            version: .http1_1,
            method: .GET,
            uri: self.nextInvocationPath,
            headers: self.defaultHeaders
        )

        context.write(self.wrapOutboundOut(.head(httpRequest)), promise: nil)
        context.write(self.wrapOutboundOut(.end(nil)), promise: nil)
        context.flush()
    }

    private func sendReportErrorRequest(requestID: String, error: any Error, context: ChannelHandlerContext) {
        // TODO: This feels quite expensive. We should be able to make this cheaper. requestIDs are fixed length
        let url = "\(Consts.invocationURLPrefix)/\(requestID)\(Consts.postErrorURLSuffix)"

        let httpRequest = HTTPRequestHead(
            version: .http1_1,
            method: .POST,
            uri: url,
            headers: self.errorHeaders
        )

        if self.reusableErrorBuffer == nil {
            self.reusableErrorBuffer = context.channel.allocator.buffer(capacity: 1024)
        } else {
            self.reusableErrorBuffer!.clear()
        }

        let errorResponse = ErrorResponse(errorType: "\(type(of: error))", errorMessage: "\(error)")
        // TODO: Write this directly into our ByteBuffer
        let bytes = errorResponse.toJSONBytes()
        self.reusableErrorBuffer!.writeBytes(bytes)

        context.write(self.wrapOutboundOut(.head(httpRequest)), promise: nil)
        context.write(self.wrapOutboundOut(.body(.byteBuffer(self.reusableErrorBuffer!))), promise: nil)
        context.write(self.wrapOutboundOut(.end(nil)), promise: nil)
        context.flush()
    }

    private func sendResponseStreamingFailure(error: any Error, context: ChannelHandlerContext) {
        let trailers: HTTPHeaders = [
            "Lambda-Runtime-Function-Error-Type": "Unhandled",
            "Lambda-Runtime-Function-Error-Body": "Requires base64",
        ]

        context.write(self.wrapOutboundOut(.end(trailers)), promise: nil)
        context.flush()
    }

    func cancelCurrentRequestAndCloseConnection() {
        fatalError("Unimplemented")
    }
}

@available(LambdaSwift 2.0, *)
extension LambdaChannelHandler: ChannelInboundHandler {
    typealias OutboundIn = Never
    typealias InboundIn = NIOHTTPClientResponseFull
    typealias OutboundOut = HTTPClientRequestPart

    func handlerAdded(context: ChannelHandlerContext) {
        if context.channel.isActive {
            self.state = .connected(context, .idle)
        }
    }

    func channelActive(context: ChannelHandlerContext) {
        switch self.state {
        case .disconnected:
            self.state = .connected(context, .idle)
        case .connected:
            break
        case .closing:
            fatalError("Invalid state: \(self.state)")
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let response = unwrapInboundIn(data)

        // handle response content

        switch self.state {
        case .connected(let context, .waitingForNextInvocation(let continuation)):
            do {
                self.logger.trace("Lambda Invocation Headers", metadata: ["headers": "\(response.head.headers)"])
                let metadata = try InvocationMetadata(headers: response.head.headers)
                self.state = .connected(context, .waitingForResponse)
                continuation.resume(returning: Invocation(metadata: metadata, event: response.body ?? ByteBuffer()))
            } catch {
                self.state = .closing

                self.delegate.connectionWillClose(channel: context.channel)
                context.close(promise: nil)
                continuation.resume(
                    throwing: LambdaRuntimeError(code: .invocationMissingMetadata, underlying: error)
                )
            }

        case .connected(let context, .sentResponse(let continuation)):
            if response.head.status == .accepted {
                self.state = .connected(context, .idle)
                continuation.resume()
            } else {
                self.state = .connected(context, .idle)
                continuation.resume(throwing: LambdaRuntimeError(code: .unexpectedStatusCodeForRequest))
            }

        case .disconnected, .closing, .connected(_, _):
            break
        }

        // As defined in RFC 7230 Section 6.3:
        // HTTP/1.1 defaults to the use of "persistent connections", allowing
        // multiple requests and responses to be carried over a single
        // connection.  The "close" connection option is used to signal that a
        // connection will not persist after the current request/response.  HTTP
        // implementations SHOULD support persistent connections.
        //
        // That's why we only assume the connection shall be closed if we receive
        // a "connection = close" header.
        let serverCloseConnection =
            response.head.headers["connection"].contains(where: { $0.lowercased() == "close" })

        let closeConnection = serverCloseConnection || response.head.version != .http1_1

        if closeConnection {
            // If we were succeeding the request promise here directly and closing the connection
            // after succeeding the promise we may run into a race condition:
            //
            // The lambda runtime will ask for the next work item directly after a succeeded post
            // response request. The desire for the next work item might be faster than the attempt
            // to close the connection. This will lead to a situation where we try to the connection
            // but the next request has already been scheduled on the connection that we want to
            // close. For this reason we postpone succeeding the promise until the connection has
            // been closed. This codepath will only be hit in the very, very unlikely event of the
            // Lambda control plane demanding to close connection. (It's more or less only
            // implemented to support http1.1 correctly.) This behavior is ensured with the test
            // `LambdaTest.testNoKeepAliveServer`.
            self.state = .closing
            self.delegate.connectionWillClose(channel: context.channel)
            context.close(promise: nil)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        self.logger.trace(
            "Channel error caught",
            metadata: [
                "error": "\(error)"
            ]
        )
        // pending responses will fail with lastError in channelInactive since we are calling context.close
        self.delegate.connectionErrorHappened(error, channel: context.channel)

        self.lastError = error
        context.channel.close(promise: nil)
    }

    func channelInactive(context: ChannelHandlerContext) {
        // fail any pending responses with last error or assume peer disconnected
        switch self.state {
        case .connected(_, let lambdaState):
            switch lambdaState {
            case .waitingForNextInvocation(let continuation):
                continuation.resume(throwing: self.lastError ?? ChannelError.ioOnClosedChannel)
            case .sentResponse(let continuation):
                continuation.resume(throwing: self.lastError ?? ChannelError.ioOnClosedChannel)
            case .idle, .sendingResponse, .waitingForResponse:
                break
            }
            self.state = .disconnected
        default:
            break
        }

        // we don't need to forward channelInactive to the delegate, as the delegate observes the
        // closeFuture
        context.fireChannelInactive()
    }
}
