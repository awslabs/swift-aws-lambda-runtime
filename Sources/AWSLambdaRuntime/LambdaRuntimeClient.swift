//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftAWSLambdaRuntime open source project
//
// Copyright (c) 2024 Apple Inc. and the SwiftAWSLambdaRuntime project authors
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

@usableFromInline
final actor LambdaRuntimeClient: LambdaRuntimeClientProtocol {
    @usableFromInline
    nonisolated let unownedExecutor: UnownedSerialExecutor

    @usableFromInline
    struct Configuration: Sendable {
        var ip: String
        var port: Int

        @usableFromInline
        init(ip: String, port: Int) {
            self.ip = ip
            self.port = port
        }
    }

    @usableFromInline
    struct Writer: LambdaRuntimeClientResponseStreamWriter, Sendable {
        private var runtimeClient: LambdaRuntimeClient

        fileprivate init(runtimeClient: LambdaRuntimeClient) {
            self.runtimeClient = runtimeClient
        }

        @usableFromInline
        func write(_ buffer: NIOCore.ByteBuffer, hasCustomHeaders: Bool = false) async throws {
            try await self.runtimeClient.write(buffer, hasCustomHeaders: hasCustomHeaders)
        }

        @usableFromInline
        func finish() async throws {
            try await self.runtimeClient.writeAndFinish(nil)
        }

        @usableFromInline
        func writeAndFinish(_ buffer: NIOCore.ByteBuffer) async throws {
            try await self.runtimeClient.writeAndFinish(buffer)
        }

        @usableFromInline
        func reportError(_ error: any Error) async throws {
            try await self.runtimeClient.reportError(error)
        }
    }

    private typealias ConnectionContinuation = CheckedContinuation<
        NIOLoopBound<LambdaChannelHandler<LambdaRuntimeClient>>, any Error
    >

    private enum ConnectionState {
        case disconnected
        case connecting([ConnectionContinuation])
        case connected(Channel, LambdaChannelHandler<LambdaRuntimeClient>)
    }

    enum LambdaState {
        /// this is the "normal" state. Transitions to `waitingForNextInvocation`
        case idle(previousRequestID: String?)
        /// this is the state while we wait for an invocation. A next call is running.
        /// Transitions to `waitingForResponse`
        case waitingForNextInvocation
        /// The invocation was forwarded to the handler and we wait for a response.
        /// Transitions to `sendingResponse` or `sentResponse`.
        case waitingForResponse(requestID: String)
        case sendingResponse(requestID: String)
        case sentResponse(requestID: String)
    }

    enum ClosingState {
        case notClosing
        case closing(CheckedContinuation<Void, Never>)
        case closed
    }

    private let eventLoop: any EventLoop
    private let logger: Logger
    private let configuration: Configuration

    private var connectionState: ConnectionState = .disconnected

    private var lambdaState: LambdaState = .idle(previousRequestID: nil)
    private var closingState: ClosingState = .notClosing

    // connections that are currently being closed. In the `run` method we must await all of them
    // being fully closed before we can return from it.
    private var closingConnections: [any Channel] = []

    @inlinable
    static func withRuntimeClient<Result>(
        configuration: Configuration,
        eventLoop: any EventLoop,
        logger: Logger,
        _ body: (LambdaRuntimeClient) async throws -> Result
    ) async throws -> Result {
        let runtime = LambdaRuntimeClient(configuration: configuration, eventLoop: eventLoop, logger: logger)
        let result: Swift.Result<Result, any Error>
        do {
            result = .success(try await body(runtime))
        } catch {
            result = .failure(error)
        }
        await runtime.close()
        return try result.get()
    }

    @usableFromInline
    init(configuration: Configuration, eventLoop: any EventLoop, logger: Logger) {
        self.unownedExecutor = eventLoop.executor.asUnownedSerialExecutor()
        self.configuration = configuration
        self.eventLoop = eventLoop
        self.logger = logger
    }

    @usableFromInline
    func close() async {
        self.logger.trace("Close lambda runtime client")

        guard case .notClosing = self.closingState else {
            return
        }
        await withCheckedContinuation { continuation in
            self.closingState = .closing(continuation)

            switch self.connectionState {
            case .disconnected:
                if self.closingConnections.isEmpty {
                    return continuation.resume()
                }

            case .connecting(let continuations):
                for continuation in continuations {
                    continuation.resume(throwing: LambdaRuntimeError(code: .closingRuntimeClient))
                }
                self.connectionState = .connecting([])

            case .connected(let channel, _):
                channel.close(mode: .all, promise: nil)
            }
        }
    }

    @usableFromInline
    func nextInvocation() async throws -> (Invocation, Writer) {

        try Task.checkCancellation()

        return try await withTaskCancellationHandler {
            switch self.lambdaState {
            case .idle:
                self.lambdaState = .waitingForNextInvocation
                let handler = try await self.makeOrGetConnection()
                let invocation = try await handler.nextInvocation()

                guard case .waitingForNextInvocation = self.lambdaState else {
                    fatalError("Invalid state: \(self.lambdaState)")
                }
                self.lambdaState = .waitingForResponse(requestID: invocation.metadata.requestID)
                return (invocation, Writer(runtimeClient: self))

            case .waitingForNextInvocation,
                .waitingForResponse,
                .sendingResponse,
                .sentResponse:
                fatalError("Invalid state: \(self.lambdaState)")
            }
        } onCancel: {
            Task {
                await self.close()
            }
        }
    }

    private func write(_ buffer: NIOCore.ByteBuffer, hasCustomHeaders: Bool = false) async throws {
        switch self.lambdaState {
        case .idle, .sentResponse:
            throw LambdaRuntimeError(code: .writeAfterFinishHasBeenSent)

        case .waitingForNextInvocation:
            fatalError("Invalid state: \(self.lambdaState)")

        case .waitingForResponse(let requestID):
            self.lambdaState = .sendingResponse(requestID: requestID)
            fallthrough

        case .sendingResponse(let requestID):
            let handler = try await self.makeOrGetConnection()
            guard case .sendingResponse(requestID) = self.lambdaState else {
                fatalError("Invalid state: \(self.lambdaState)")
            }
            return try await handler.writeResponseBodyPart(
                buffer,
                requestID: requestID,
                hasCustomHeaders: hasCustomHeaders
            )
        }
    }

    private func writeAndFinish(_ buffer: NIOCore.ByteBuffer?) async throws {
        switch self.lambdaState {
        case .idle, .sentResponse:
            throw LambdaRuntimeError(code: .finishAfterFinishHasBeenSent)

        case .waitingForNextInvocation:
            fatalError("Invalid state: \(self.lambdaState)")

        case .waitingForResponse(let requestID):
            fallthrough

        case .sendingResponse(let requestID):
            self.lambdaState = .sentResponse(requestID: requestID)
            let handler = try await self.makeOrGetConnection()
            guard case .sentResponse(requestID) = self.lambdaState else {
                fatalError("Invalid state: \(self.lambdaState)")
            }
            try await handler.finishResponseRequest(finalData: buffer, requestID: requestID)
            guard case .sentResponse(requestID) = self.lambdaState else {
                fatalError("Invalid state: \(self.lambdaState)")
            }
            self.lambdaState = .idle(previousRequestID: requestID)
        }
    }

    private func reportError(_ error: any Error) async throws {
        switch self.lambdaState {
        case .idle, .waitingForNextInvocation, .sentResponse:
            fatalError("Invalid state: \(self.lambdaState)")

        case .waitingForResponse(let requestID):
            fallthrough

        case .sendingResponse(let requestID):
            self.lambdaState = .sentResponse(requestID: requestID)
            let handler = try await self.makeOrGetConnection()
            guard case .sentResponse(requestID) = self.lambdaState else {
                fatalError("Invalid state: \(self.lambdaState)")
            }
            try await handler.reportError(error, requestID: requestID)
            guard case .sentResponse(requestID) = self.lambdaState else {
                fatalError("Invalid state: \(self.lambdaState)")
            }
            self.lambdaState = .idle(previousRequestID: requestID)
        }
    }

    private func channelClosed(_ channel: any Channel) {
        switch (self.connectionState, self.closingState) {
        case (_, .closed):
            fatalError("Invalid state: \(self.connectionState), \(self.closingState)")

        case (.disconnected, .notClosing):
            if let index = self.closingConnections.firstIndex(where: { $0 === channel }) {
                self.closingConnections.remove(at: index)
            }

        case (.disconnected, .closing(let continuation)):
            if let index = self.closingConnections.firstIndex(where: { $0 === channel }) {
                self.closingConnections.remove(at: index)
            }

            if self.closingConnections.isEmpty {
                self.closingState = .closed
                continuation.resume()
            }

        case (.connecting(let array), .notClosing):
            self.connectionState = .disconnected
            for continuation in array {
                continuation.resume(throwing: LambdaRuntimeError(code: .connectionToControlPlaneLost))
            }

        case (.connecting(let array), .closing(let continuation)):
            self.connectionState = .disconnected
            precondition(array.isEmpty, "If we are closing we should have failed all connection attempts already")
            if self.closingConnections.isEmpty {
                self.closingState = .closed
                continuation.resume()
            }

        case (.connected, .notClosing):
            self.connectionState = .disconnected

        case (.connected, .closing(let continuation)):
            self.connectionState = .disconnected

            if self.closingConnections.isEmpty {
                self.closingState = .closed
                continuation.resume()
            }
        }
    }

    private func makeOrGetConnection() async throws -> LambdaChannelHandler<LambdaRuntimeClient> {
        switch self.connectionState {
        case .disconnected:
            self.connectionState = .connecting([])
            break
        case .connecting(var array):
            // Since we do get sequential invocations this case normally should never be hit.
            // We'll support it anyway.
            let loopBound = try await withCheckedThrowingContinuation { (continuation: ConnectionContinuation) in
                array.append(continuation)
                self.connectionState = .connecting(array)
            }
            return loopBound.value
        case .connected(_, let handler):
            return handler
        }

        let bootstrap = ClientBootstrap(group: self.eventLoop)
            .channelInitializer { channel in
                do {
                    try channel.pipeline.syncOperations.addHTTPClientHandlers()
                    // Lambda quotas... An invocation payload is maximal 6MB in size:
                    //   https://docs.aws.amazon.com/lambda/latest/dg/gettingstarted-limits.html
                    try channel.pipeline.syncOperations.addHandler(
                        NIOHTTPClientResponseAggregator(maxContentLength: 6 * 1024 * 1024)
                    )
                    try channel.pipeline.syncOperations.addHandler(
                        LambdaChannelHandler(
                            delegate: self,
                            logger: self.logger,
                            configuration: self.configuration
                        )
                    )
                    return channel.eventLoop.makeSucceededFuture(())
                } catch {
                    return channel.eventLoop.makeFailedFuture(error)
                }
            }
            .connectTimeout(.seconds(2))

        do {
            // connect directly via socket address to avoid happy eyeballs (perf)
            let address = try SocketAddress(ipAddress: self.configuration.ip, port: self.configuration.port)
            let channel = try await bootstrap.connect(to: address).get()
            let handler = try channel.pipeline.syncOperations.handler(
                type: LambdaChannelHandler<LambdaRuntimeClient>.self
            )
            self.logger.trace(
                "Connection to control plane created",
                metadata: [
                    "lambda_port": "\(self.configuration.port)",
                    "lambda_ip": "\(self.configuration.ip)",
                ]
            )
            channel.closeFuture.whenComplete { result in
                self.assumeIsolated { runtimeClient in
                    // close the channel
                    runtimeClient.channelClosed(channel)
                    runtimeClient.connectionState = .disconnected
                }
            }

            switch self.connectionState {
            case .disconnected, .connected:
                fatalError("Unexpected state: \(self.connectionState)")

            case .connecting(let array):
                self.connectionState = .connected(channel, handler)
                defer {
                    let loopBound = NIOLoopBound(handler, eventLoop: self.eventLoop)
                    for continuation in array {
                        continuation.resume(returning: loopBound)
                    }
                }
                return handler
            }
        } catch {

            switch self.connectionState {
            case .disconnected, .connected:
                fatalError("Unexpected state: \(self.connectionState)")

            case .connecting(let array):
                self.connectionState = .disconnected
                defer {
                    for continuation in array {
                        continuation.resume(throwing: error)
                    }
                }
                throw error
            }
        }
    }
}

extension LambdaRuntimeClient: LambdaChannelHandlerDelegate {
    nonisolated func connectionErrorHappened(_ error: any Error, channel: any Channel) {}

    nonisolated func connectionWillClose(channel: any Channel) {
        self.assumeIsolated { isolated in
            switch isolated.connectionState {
            case .disconnected:
                // this case should never happen. But whatever
                if channel.isActive {
                    isolated.closingConnections.append(channel)
                }

            case .connecting(let continuations):
                // this case should never happen. But whatever
                if channel.isActive {
                    isolated.closingConnections.append(channel)
                }

                for continuation in continuations {
                    continuation.resume(throwing: LambdaRuntimeError(code: .connectionToControlPlaneLost))
                }

            case .connected(let stateChannel, _):
                guard channel === stateChannel else {
                    isolated.closingConnections.append(channel)
                    return
                }

                isolated.connectionState = .disconnected
            }
        }
    }
}
