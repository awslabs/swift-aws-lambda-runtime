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

#if LocalServerSupport
import Logging
import NIOCore
import NIOHTTP1
import NIOPosix

// for UUID
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

// This functionality is designed for local testing when the LocalServerSupport trait is enabled.

// For example:
// try Lambda.withLocalServer {
//     try await LambdaRuntimeClient.withRuntimeClient(
//         configuration: .init(ip: "127.0.0.1", port: 7000),
//         eventLoop: self.eventLoop,
//         logger: self.logger
//     ) { runtimeClient in
//         try await Lambda.runLoop(
//             runtimeClient: runtimeClient,
//             handler: handler,
//             logger: self.logger
//         )
//     }
// }
@available(LambdaSwift 2.0, *)
extension Lambda {
    /// Execute code in the context of a mock Lambda server.
    ///
    /// - parameters:
    ///     - host: the hostname or IP address to listen on
    ///     - port: the TCP port to listen to
    ///     - invocationEndpoint: The endpoint to post events to.
    ///     - body: Code to run within the context of the mock server. Typically this would be a Lambda.run function call.
    ///
    /// - note: This API is designed strictly for local testing when the LocalServerSupport trait is enabled.
    @usableFromInline
    static func withLocalServer(
        host: String,
        port: Int,
        invocationEndpoint: String? = nil,
        logger: Logger,
        _ body: sending @escaping () async throws -> Void
    ) async throws {
        do {
            try await LambdaHTTPServer.withLocalServer(
                host: host,
                port: port,
                invocationEndpoint: invocationEndpoint,
                logger: logger
            ) {
                try await body()
            }
        } catch let error as ChannelError {
            // when this server is part of a ServiceLifeCycle group
            // and user presses CTRL-C, this error is thrown
            // The error description is "I/O on closed channel"
            // TODO: investigate and solve the root cause
            // because this server is used only for local tests
            // and the error happens when we shutdown the server, I decided to ignore it at the moment.
            logger.trace("Ignoring ChannelError during local server shutdown: \(error)")
        }
    }
}

// MARK: - Local HTTP Server

/// An HTTP server that behaves like the AWS Lambda service for local testing.
/// This server is used to simulate the AWS Lambda service for local testing but also to accept invocation requests from the lambda client.
///
/// It accepts three types of requests from the Lambda function (through the LambdaRuntimeClient):
/// 1. GET /next - the lambda function polls this endpoint to get the next invocation request
/// 2. POST /:requestId/response - the lambda function posts the response to the invocation request
/// 3. POST /:requestId/error - the lambda function posts an error response to the invocation request
///
/// It also accepts one type of request from the client invoking the lambda function:
/// 1. POST /invoke - the client posts the event to the lambda function
///
/// This server passes the data received from /invoke POST request to the lambda function (GET /next) and then forwards the response back to the client.
@available(LambdaSwift 2.0, *)
internal struct LambdaHTTPServer {
    private let invocationEndpoint: String

    private let invocationPool = Pool<LocalServerInvocation>(name: "Invocation Pool")
    private let responsePool = Pool<LocalServerResponse>(name: "Response Pool")

    private init(
        invocationEndpoint: String?
    ) {
        self.invocationEndpoint = invocationEndpoint ?? "/invoke"
    }

    private enum TaskResult<Result: Sendable>: Sendable {
        case closureResult(Swift.Result<Result, any Error>)
        case serverReturned(Swift.Result<Void, any Error>)
    }

    fileprivate struct UnsafeTransferBox<Value>: @unchecked Sendable {
        let value: Value

        init(value: sending Value) {
            self.value = value
        }
    }

    static func withLocalServer<Result: Sendable>(
        host: String,
        port: Int,
        invocationEndpoint: String?,
        eventLoopGroup: MultiThreadedEventLoopGroup = .singleton,
        logger: Logger,
        _ closure: sending @escaping () async throws -> Result
    ) async throws -> Result {

        let server = LambdaHTTPServer(invocationEndpoint: invocationEndpoint)

        // Use traditional callback-based API to avoid NIO async channel cancellation race
        // See: https://github.com/apple/swift-nio/issues/2637
        let bootstrap = ServerBootstrap(group: eventLoopGroup)
            .serverChannelOption(.backlog, value: 256)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(.maxMessagesPerRead, value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline(withErrorHandling: true).flatMap { _ in
                    // Handle connection in a detached task
                    do {
                        let asyncChannel = try NIOAsyncChannel(
                            wrappingChannelSynchronously: channel,
                            configuration: NIOAsyncChannel.Configuration(
                                inboundType: HTTPServerRequestPart.self,
                                outboundType: HTTPServerResponsePart.self
                            )
                        )

                        Task.detached {
                            await server.handleConnection(channel: asyncChannel, logger: logger)
                        }

                        return channel.eventLoop.makeSucceededVoidFuture()
                    } catch {
                        return channel.eventLoop.makeFailedFuture(error)
                    }
                }
            }

        let channel = try await bootstrap.bind(host: host, port: port).get()

        // it's ok to keep this at `info` level because it is only used for local testing and unit tests
        logger.info(
            "Server started and listening",
            metadata: [
                "host": "\(channel.localAddress?.ipAddress?.debugDescription ?? "")",
                "port": "\(channel.localAddress?.port ?? 0)",
            ]
        )

        // Sadly the Swift compiler does not understand that the passed in closure will only be
        // invoked once. Because of this we need an unsafe transfer box here. Buuuh!
        let closureBox = UnsafeTransferBox(value: closure)
        let result = await withTaskGroup(of: TaskResult<Result>.self, returning: Swift.Result<Result, any Error>.self) {
            group in

            // this Task will run the content of the closure we received, typically the Lambda Runtime Client HTTP
            group.addTask {
                let c = closureBox.value
                do {
                    let result = try await c()
                    return .closureResult(.success(result))
                } catch {
                    return .closureResult(.failure(error))
                }
            }

            // Server task - just wait for channel to close
            group.addTask {
                do {
                    try await channel.closeFuture.get()
                    return .serverReturned(.success(()))
                } catch {
                    return .serverReturned(.failure(error))
                }
            }

            // Now that the local HTTP server and LambdaHandler tasks are started, wait for the
            // first of the two that will terminate.
            // When first task completes, close the server channel and wait for the other task.
            // Note: we intentionally do not call `group.cancelAll()` here. Closing the channel causes
            // the server task (which is awaiting `channel.closeFuture`) to complete naturally, and
            // we then wait for the remaining task to finish via `group.next()`.
            let serverOrHandlerResult1 = await group.next()!

            channel.close(promise: nil)

            server.invocationPool.cancelAll()
            server.responsePool.cancelAll()

            let serverOrHandlerResult2 = await group.next()!

            switch serverOrHandlerResult1 {
            case .closureResult(let result):
                return result

            case .serverReturned(let result):
                if let error = result.maybeError {
                    logger.error("Server error: \(error)")
                }

                switch serverOrHandlerResult2 {
                case .closureResult(let result):
                    return result

                case .serverReturned:
                    fatalError("Only one task is a server, and only one can return `serverReturned`")
                }
            }
        }

        logger.info("Server shutting down")
        if case .failure(let error) = result {
            logger.error("Error during server shutdown: \(error)")
        }
        return try result.get()
    }

    /// This method handles individual TCP connections
    private func handleConnection(
        channel: NIOAsyncChannel<HTTPServerRequestPart, HTTPServerResponsePart>,
        logger: Logger
    ) async {

        var requestHead: HTTPRequestHead!
        var requestBody: ByteBuffer?
        var requestId: String?

        do {
            try await channel.executeThenClose { inbound, outbound in
                for try await inboundData in inbound {
                    switch inboundData {
                    case .head(let head):
                        requestHead = head
                        requestId = getRequestId(from: requestHead)

                        // for streaming requests, push a partial head response
                        if self.isStreamingResponse(requestHead) {
                            self.responsePool.push(
                                LocalServerResponse(
                                    id: requestId,
                                    status: .ok
                                )
                            )
                        }

                    case .body(let body):
                        precondition(requestHead != nil, "Received .body without .head")

                        // if this is a request from a Streaming Lambda Handler,
                        // stream the response instead of buffering it
                        if self.isStreamingResponse(requestHead) {
                            self.responsePool.push(
                                LocalServerResponse(id: requestId, body: body)
                            )
                        } else {
                            requestBody.setOrWriteImmutableBuffer(body)
                        }

                    case .end:
                        precondition(requestHead != nil, "Received .end without .head")

                        if self.isStreamingResponse(requestHead) {
                            // for streaming response, send the final response
                            self.responsePool.push(
                                LocalServerResponse(id: requestId, final: true)
                            )

                            // Send acknowledgment back to Lambda runtime client for streaming END
                            // This is the single HTTP response to the chunked HTTP request
                            try await self.sendResponse(
                                .init(id: requestId, status: .accepted, final: true),
                                outbound: outbound,
                                logger: logger
                            )
                        } else {
                            // process the buffered response for non streaming requests
                            try await self.processRequestAndSendResponse(
                                head: requestHead,
                                body: requestBody,
                                outbound: outbound,
                                logger: logger
                            )
                        }

                        // reset the request state for next request
                        requestHead = nil
                        requestBody = nil
                        requestId = nil
                    }
                }
            }
        } catch let error as CancellationError {
            logger.trace("The task was cancelled", metadata: ["error": "\(error)"])
        } catch {
            logger.error("Hit error: \(error)")
        }
    }

    /// This function checks if the request is a streaming response request
    /// verb = POST, uri = :requestId/response, HTTP Header contains "Transfer-Encoding: chunked"
    private func isStreamingResponse(_ requestHead: HTTPRequestHead) -> Bool {
        requestHead.method == .POST && requestHead.uri.hasSuffix(Consts.postResponseURLSuffix)
            && requestHead.headers.contains(name: "Transfer-Encoding")
            && (requestHead.headers["Transfer-Encoding"].contains("chunked")
                || requestHead.headers["Transfer-Encoding"].contains("Chunked"))
    }

    /// This function parses and returns the requestId or nil if the request doesn't contain a requestId
    private func getRequestId(from head: HTTPRequestHead) -> String? {
        let parts = head.uri.split(separator: "/")
        return parts.count > 2 ? String(parts[parts.count - 2]) : nil
    }
    /// This function process the URI request sent by the client and by the Lambda function
    ///
    /// It enqueues the client invocation and iterate over the invocation queue when the Lambda function sends /next request
    /// It answers the /:requestId/response and /:requestId/error requests sent by the Lambda function but do not process the body
    ///
    /// - Parameters:
    ///   - head: the HTTP request head
    ///   - body: the HTTP request body
    /// - Throws:
    /// - Returns: the response to send back to the client or the Lambda function
    private func processRequestAndSendResponse(
        head: HTTPRequestHead,
        body: ByteBuffer?,
        outbound: NIOAsyncChannelOutboundWriter<HTTPServerResponsePart>,
        logger: Logger
    ) async throws {

        var logger = logger
        logger[metadataKey: "URI"] = "\(head.method) \(head.uri)"
        if let body {
            logger.trace(
                "Processing request",
                metadata: ["Body": "\(String(buffer: body))"]
            )
        } else {
            logger.trace("Processing request")
        }

        switch (head.method, head.uri) {

        //
        // client invocations
        //
        // client POST /invoke
        case (.POST, let url) where url.hasSuffix(self.invocationEndpoint):
            guard let body else {
                return try await sendResponse(
                    .init(status: .badRequest, final: true),
                    outbound: outbound,
                    logger: logger
                )
            }
            // we always accept the /invoke request and push them to the pool
            let requestId = UUID().uuidString
            logger[metadataKey: "requestId"] = "\(requestId)"

            logger.trace("/invoke received invocation, pushing it to the pool and wait for a lambda response")
            self.invocationPool.push(LocalServerInvocation(requestId: requestId, request: body))

            // wait for the lambda function to process the request
            // Handle streaming responses by collecting all chunks for this requestId
            do {
                var isComplete = false
                while !isComplete {
                    let response = try await self.responsePool.next(for: requestId)
                    logger[metadataKey: "response_requestId"] = "\(response.requestId ?? "nil")"
                    logger.trace("Received response chunk to return to client")

                    // send the response chunk to the client
                    try await self.sendResponse(response, outbound: outbound, logger: logger)

                    if response.final == true {
                        logger.trace("/invoke complete, returning")
                        isComplete = true
                    }
                }
            } catch let error as LambdaHTTPServer.Pool<LambdaHTTPServer.LocalServerResponse>.PoolError {
                logger.trace("PoolError caught", metadata: ["error": "\(error)"])
                // detect concurrent invocations of POST and gently decline the requests while we're processing one.
                let response = LocalServerResponse(
                    id: requestId,
                    status: .internalServerError,
                    body: ByteBuffer(
                        string:
                            "\(error): It is not allowed to invoke multiple Lambda function executions in parallel. (The Lambda runtime environment on AWS will never do that)"
                    )
                )
                try await self.sendResponse(response, outbound: outbound, logger: logger)
            }

        // client uses incorrect HTTP method
        case (_, let url) where url.hasSuffix(self.invocationEndpoint):
            return try await sendResponse(
                .init(status: .methodNotAllowed, final: true),
                outbound: outbound,
                logger: logger
            )

        //
        // lambda invocations
        //

        // /next endpoint is called by the lambda polling for work
        // this call only returns when there is a task to give to the lambda function
        case (.GET, let url) where url.hasSuffix(Consts.getNextInvocationURLSuffix):

            // pop the tasks from the queue
            logger.trace("/next waiting for /invoke")
            for try await invocation in self.invocationPool {
                logger[metadataKey: "requestId"] = "\(invocation.requestId)"
                logger.trace("/next retrieved invocation")
                // tell the lambda function we accepted the invocation
                try await sendResponse(invocation.acceptedResponse(), outbound: outbound, logger: logger)
                logger.trace("/next accepted, returning")
                return
            }
            // What todo when there is no more tasks to process?
            // This should not happen as the async iterator blocks until there is a task to process
            fatalError("No more invocations to process - the async for loop should not return")

        // :requestId/response endpoint is called by the lambda posting the response
        case (.POST, let url) where url.hasSuffix(Consts.postResponseURLSuffix):
            guard let requestId = getRequestId(from: head) else {
                // the request is malformed, since we were expecting a requestId in the path
                return try await sendResponse(
                    .init(status: .badRequest, final: true),
                    outbound: outbound,
                    logger: logger
                )
            }
            // enqueue the lambda function response to be served as response to the client /invoke
            logger.trace("/:requestId/response received response", metadata: ["requestId": "\(requestId)"])
            self.responsePool.push(
                LocalServerResponse(
                    id: requestId,
                    status: .accepted,
                    // the local server has no mecanism to collect headers set by the lambda function
                    headers: HTTPHeaders(),
                    body: body,
                    final: true
                )
            )

            // tell the Lambda function we accepted the response
            return try await sendResponse(
                .init(id: requestId, status: .accepted, final: true),
                outbound: outbound,
                logger: logger
            )

        // :requestId/error endpoint is called by the lambda posting an error response
        // we accept all requestId and we do not handle the body, we just acknowledge the request
        case (.POST, let url) where url.hasSuffix(Consts.postErrorURLSuffix):
            guard let requestId = getRequestId(from: head) else {
                // the request is malformed, since we were expecting a requestId in the path
                return try await sendResponse(
                    .init(status: .badRequest, final: true),
                    outbound: outbound,
                    logger: logger
                )
            }
            // enqueue the lambda function response to be served as response to the client /invoke
            logger.trace("/:requestId/response received response", metadata: ["requestId": "\(requestId)"])
            self.responsePool.push(
                LocalServerResponse(
                    id: requestId,
                    status: .internalServerError,
                    headers: HTTPHeaders([("Content-Type", "application/json")]),
                    body: body,
                    final: true
                )
            )

            return try await sendResponse(.init(status: .accepted, final: true), outbound: outbound, logger: logger)

        // unknown call
        default:
            return try await sendResponse(.init(status: .notFound, final: true), outbound: outbound, logger: logger)
        }
    }

    private func sendResponse(
        _ response: LocalServerResponse,
        outbound: NIOAsyncChannelOutboundWriter<HTTPServerResponsePart>,
        logger: Logger
    ) async throws {
        var logger = logger
        logger[metadataKey: "requestId"] = "\(response.requestId ?? "nil")"
        logger.trace("Writing response for \(response.status?.code ?? 0)")

        var headers = response.headers ?? HTTPHeaders()
        if let body = response.body {
            headers.add(name: "Content-Length", value: "\(body.readableBytes)")
        }

        if let status = response.status {
            logger.trace("Sending status and headers")
            try await outbound.write(
                HTTPServerResponsePart.head(
                    HTTPResponseHead(
                        version: .init(major: 1, minor: 1),
                        status: status,
                        headers: headers
                    )
                )
            )
        }

        if let body = response.body {
            logger.trace("Sending body")
            try await outbound.write(HTTPServerResponsePart.body(.byteBuffer(body)))
        }

        if response.final {
            logger.trace("Sending end")
            try await outbound.write(HTTPServerResponsePart.end(nil))
        }
    }

    struct LocalServerResponse: Sendable {
        let requestId: String?
        let status: HTTPResponseStatus?
        let headers: HTTPHeaders?
        let body: ByteBuffer?
        let final: Bool
        init(
            id: String? = nil,
            status: HTTPResponseStatus? = nil,
            headers: HTTPHeaders? = nil,
            body: ByteBuffer? = nil,
            final: Bool = false
        ) {
            self.requestId = id
            self.status = status
            self.headers = headers
            self.body = body
            self.final = final
        }
    }

    struct LocalServerInvocation: Sendable {
        let requestId: String
        let request: ByteBuffer

        func acceptedResponse() -> LocalServerResponse {

            // required headers
            let headers = HTTPHeaders([
                (AmazonHeaders.requestID, self.requestId),
                (
                    AmazonHeaders.invokedFunctionARN,
                    "arn:aws:lambda:us-east-1:\(Int16.random(in: Int16.min ... Int16.max)):function:custom-runtime"
                ),
                (AmazonHeaders.traceID, "Root=\(AmazonHeaders.generateXRayTraceID());Sampled=1"),
                (AmazonHeaders.deadline, "\(LambdaClock.maxLambdaDeadline)"),
            ])

            return LocalServerResponse(
                id: self.requestId,
                status: .accepted,
                headers: headers,
                body: self.request,
                final: true
            )
        }
    }
}

extension Result {
    var maybeError: Failure? {
        switch self {
        case .success:
            return nil
        case .failure(let error):
            return error
        }
    }
}
#endif
