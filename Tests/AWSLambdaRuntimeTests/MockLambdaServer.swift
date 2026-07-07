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

@testable import AWSLambdaRuntime

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

func withMockServer<Result>(
    behaviour: some LambdaServerBehavior,
    port: Int = 0,
    keepAlive: Bool = true,
    _ body: (_ port: Int) async throws -> Result
) async throws -> Result {
    let eventLoopGroup = NIOSingletons.posixEventLoopGroup
    let server = MockLambdaServer(behavior: behaviour, port: port, keepAlive: keepAlive, eventLoopGroup: eventLoopGroup)
    let port = try await server.start()

    let result: Swift.Result<Result, any Error>
    do {
        result = .success(try await body(port))
    } catch {
        result = .failure(error)
    }

    try? await server.stop()
    return try result.get()
}

final class MockLambdaServer<Behavior: LambdaServerBehavior> {
    private let logger = Logger(label: "MockLambdaServer")
    private let behavior: Behavior
    private let host: String
    private let port: Int
    private let keepAlive: Bool
    private let group: any EventLoopGroup

    private var channel: (any Channel)?
    private var shutdown = false

    init(
        behavior: Behavior,
        host: String = "127.0.0.1",
        port: Int = 0,
        keepAlive: Bool = true,
        eventLoopGroup: MultiThreadedEventLoopGroup
    ) {
        self.group = NIOSingletons.posixEventLoopGroup
        self.behavior = behavior
        self.host = host
        self.port = port
        self.keepAlive = keepAlive
    }

    deinit {
        assert(shutdown)
    }

    fileprivate func start() async throws -> Int {
        let logger = self.logger
        let keepAlive = self.keepAlive
        let behavior = self.behavior

        let channel = try await ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .childChannelInitializer { channel in
                do {
                    try channel.pipeline.syncOperations.configureHTTPServerPipeline(withErrorHandling: true)
                    try channel.pipeline.syncOperations.addHandler(
                        HTTPHandler(logger: logger, keepAlive: keepAlive, behavior: behavior)
                    )
                    return channel.eventLoop.makeSucceededVoidFuture()
                } catch {
                    return channel.eventLoop.makeFailedFuture(error)
                }
            }
            .bind(host: self.host, port: self.port)
            .get()

        self.channel = channel
        guard let localAddress = channel.localAddress else {
            throw ServerError.cantBind
        }
        self.logger.trace("\(self) started and listening on \(localAddress)")
        return localAddress.port!
    }

    fileprivate func stop() async throws {
        self.logger.trace("stopping \(self)")
        let channel = self.channel!
        try? await channel.close().get()
        self.shutdown = true
        self.logger.trace("\(self) stopped")
    }
}

final class HTTPHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let logger: Logger
    private let keepAlive: Bool
    private let behavior: any LambdaServerBehavior

    private var pending = CircularBuffer<(head: HTTPRequestHead, body: ByteBuffer?)>()

    init(logger: Logger, keepAlive: Bool, behavior: any LambdaServerBehavior) {
        self.logger = logger
        self.keepAlive = keepAlive
        self.behavior = behavior
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let requestPart = unwrapInboundIn(data)

        switch requestPart {
        case .head(let head):
            self.pending.append((head: head, body: nil))
        case .body(var buffer):
            var request = self.pending.removeFirst()
            if request.body == nil {
                request.body = buffer
            } else {
                request.body!.writeBuffer(&buffer)
            }
            self.pending.prepend(request)
        case .end:
            let request = self.pending.removeFirst()
            self.processRequest(context: context, request: request)
        }
    }

    func processRequest(context: ChannelHandlerContext, request: (head: HTTPRequestHead, body: ByteBuffer?)) {
        self.logger.trace("\(self) processing \(request.head.uri)")

        let requestBody = request.body.flatMap { (buffer: ByteBuffer) -> String? in
            var buffer = buffer
            return buffer.readString(length: buffer.readableBytes)
        }

        var responseStatus: HTTPResponseStatus
        var responseBody: String?
        var responseHeaders: [(String, String)]?
        var disconnectAfterSend = false

        // Handle post-init-error first to avoid matching the less specific post-error suffix.
        if request.head.uri.hasSuffix(Consts.postInitErrorURL) {
            guard let json = requestBody, let error = ErrorResponse.fromJson(json) else {
                return self.writeResponse(context: context, status: .badRequest)
            }
            switch self.behavior.processInitError(error: error) {
            case .success:
                responseStatus = .accepted
            case .failure(let error):
                responseStatus = .init(statusCode: error.rawValue)
            }
        } else if request.head.uri.hasSuffix(Consts.getNextInvocationURLSuffix) {
            switch self.behavior.getInvocation() {
            case .success(let (requestId, result)):
                if requestId == "timeout" {
                    usleep((UInt32(result) ?? 0) * 1000)
                } else if requestId == "disconnect" {
                    return context.close(promise: nil)
                }
                responseStatus = .ok
                responseBody = result
                let deadline = Date(timeIntervalSinceNow: 60).millisSinceEpoch
                let traceID: String
                if #available(macOS 15.0, *) {
                    traceID = "Root=\(AmazonHeaders.generateXRayTraceID());Sampled=1"
                } else {
                    traceID = "Root=1-00000000-000000000000000000000000;Sampled=1"
                }
                responseHeaders = [
                    (AmazonHeaders.requestID, requestId),
                    (AmazonHeaders.invokedFunctionARN, "arn:aws:lambda:us-east-1:123456789012:function:custom-runtime"),
                    (AmazonHeaders.traceID, traceID),
                    (AmazonHeaders.deadline, String(deadline)),
                ]
            case .failure(let error):
                responseStatus = .init(statusCode: error.rawValue)
            }
        } else if request.head.uri.hasSuffix(Consts.postResponseURLSuffix) {
            guard let requestId = request.head.uri.split(separator: "/").dropFirst(3).first else {
                return self.writeResponse(context: context, status: .badRequest)
            }

            // Capture headers for testing
            var behavior = self.behavior
            behavior.captureHeaders(request.head.headers)

            switch behavior.processResponse(requestId: String(requestId), response: requestBody) {
            case .success(let next):
                responseStatus = .accepted
                if next == "delayed-disconnect" {
                    disconnectAfterSend = true
                }
            case .failure(let error):
                responseStatus = .init(statusCode: error.rawValue)
            }
        } else if request.head.uri.hasSuffix(Consts.postErrorURLSuffix) {
            guard let requestId = request.head.uri.split(separator: "/").dropFirst(3).first,
                let json = requestBody,
                let error = ErrorResponse.fromJson(json)
            else {
                return self.writeResponse(context: context, status: .badRequest)
            }
            switch self.behavior.processError(requestId: String(requestId), error: error) {
            case .success():
                responseStatus = .accepted
            case .failure(let error):
                responseStatus = .init(statusCode: error.rawValue)
            }
        } else {
            responseStatus = .notFound
        }
        self.writeResponse(
            context: context,
            status: responseStatus,
            headers: responseHeaders,
            body: responseBody,
            closeConnection: disconnectAfterSend
        )
    }

    func writeResponse(
        context: ChannelHandlerContext,
        status: HTTPResponseStatus,
        headers: [(String, String)]? = nil,
        body: String? = nil,
        closeConnection: Bool = false
    ) {
        var headers = HTTPHeaders(headers ?? [])
        headers.add(name: "Content-Length", value: "\(body?.utf8.count ?? 0)")
        if !self.keepAlive {
            headers.add(name: "Connection", value: "close")
        }
        let head = HTTPResponseHead(version: HTTPVersion(major: 1, minor: 1), status: status, headers: headers)

        let logger = self.logger
        context.write(wrapOutboundOut(.head(head))).whenFailure { error in
            logger.error("write error \(error)")
        }

        if let b = body {
            var buffer = context.channel.allocator.buffer(capacity: b.utf8.count)
            buffer.writeString(b)
            context.write(wrapOutboundOut(.body(.byteBuffer(buffer)))).whenFailure { error in
                logger.error("write error \(error)")
            }
        }

        let loopBoundContext = NIOLoopBound(context, eventLoop: context.eventLoop)
        let keepAlive = self.keepAlive
        context.writeAndFlush(wrapOutboundOut(.end(nil))).whenComplete { result in
            let context = loopBoundContext.value
            if closeConnection {
                context.close(promise: nil)
                return
            }

            if case .failure(let error) = result {
                logger.error("write error \(error)")
            }

            if !keepAlive {
                context.close().whenFailure { error in
                    logger.error("close error \(error)")
                }
            }
        }
    }
}

protocol LambdaServerBehavior: Sendable {
    func getInvocation() -> GetInvocationResult
    func processResponse(requestId: String, response: String?) -> Result<String?, ProcessResponseError>
    func processError(requestId: String, error: ErrorResponse) -> Result<Void, ProcessErrorError>
    func processInitError(error: ErrorResponse) -> Result<Void, ProcessErrorError>

    // Optional method to capture headers for testing
    mutating func captureHeaders(_ headers: HTTPHeaders)
}

// Default implementation for backward compatibility
extension LambdaServerBehavior {
    mutating func captureHeaders(_ headers: HTTPHeaders) {
        // Default implementation does nothing
    }
}

typealias GetInvocationResult = Result<(String, String), GetWorkError>

enum GetWorkError: Int, Error {
    case badRequest = 400
    case tooManyRequests = 429
    case internalServerError = 500
}

enum ProcessResponseError: Int, Error {
    case badRequest = 400
    case payloadTooLarge = 413
    case tooManyRequests = 429
    case internalServerError = 500
}

enum ProcessErrorError: Int, Error {
    case invalidErrorShape = 299
    case badRequest = 400
    case internalServerError = 500
}

enum ServerError: Error {
    case notReady
    case cantBind
}

extension ErrorResponse {
    fileprivate static func fromJson(_ s: String) -> ErrorResponse? {
        let decoder = JSONDecoder()
        do {
            if let data = s.data(using: .utf8) {
                return try decoder.decode(ErrorResponse.self, from: data)
            } else {
                return nil
            }
        } catch {
            return nil
        }
    }
}
