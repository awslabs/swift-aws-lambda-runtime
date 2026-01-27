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
import Synchronization

// for UUID and Date
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@available(LambdaSwift 2.0, *)
@main
struct HttpServer {
    /// The server's host. (default: 127.0.0.1)
    private let host: String
    /// The server's port. (default: 7000)
    private let port: Int
    /// The server's event loop group. (default: MultiThreadedEventLoopGroup.singleton)
    private let eventLoopGroup: MultiThreadedEventLoopGroup
    /// the mode. Are we mocking a server for a Lambda function that expects a String or a JSON document? (default: string)
    private let mode: Mode
    /// the number of invocations this server must accept before shutting down (default: 1)
    private let maxInvocations: Int
    /// the logger (control verbosity with LOG_LEVEL environment variable)
    private let logger: Logger

    static func main() async throws {
        var log = Logger(label: "MockServer")
        log.logLevel = env("LOG_LEVEL").flatMap { .init(rawValue: $0) } ?? .info

        let server = HttpServer(
            host: env("HOST") ?? "127.0.0.1",
            port: env("PORT").flatMap(Int.init) ?? 7000,
            eventLoopGroup: .singleton,
            mode: env("MODE").flatMap(Mode.init) ?? .string,
            maxInvocations: env("MAX_INVOCATIONS").flatMap(Int.init) ?? 1,
            logger: log
        )
        try await server.run()
    }

    /// This method starts the server and handles one unique incoming connections
    /// The Lambda function will send two HTTP requests over this connection: one for the next invocation and one for the response.
    private func run() async throws {
        let channel = try await ServerBootstrap(group: self.eventLoopGroup)
            .serverChannelOption(.backlog, value: 256)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(.maxMessagesPerRead, value: 1)
            .bind(
                host: self.host,
                port: self.port
            ) { channel in
                channel.eventLoop.makeCompletedFuture {

                    try channel.pipeline.syncOperations.configureHTTPServerPipeline(
                        withErrorHandling: true
                    )

                    return try NIOAsyncChannel(
                        wrappingChannelSynchronously: channel,
                        configuration: NIOAsyncChannel.Configuration(
                            inboundType: HTTPServerRequestPart.self,
                            outboundType: HTTPServerResponsePart.self
                        )
                    )
                }
            }

        logger.info(
            "Server started and listening",
            metadata: [
                "host": "\(channel.channel.localAddress?.ipAddress?.debugDescription ?? "")",
                "port": "\(channel.channel.localAddress?.port ?? 0)",
                "maxInvocations": "\(self.maxInvocations)",
            ]
        )

        // We are handling each incoming connection in a separate child task. It is important
        // to use a discarding task group here which automatically discards finished child tasks.
        // A normal task group retains all child tasks and their outputs in memory until they are
        // consumed by iterating the group or by exiting the group. Since, we are never consuming
        // the results of the group we need the group to automatically discard them; otherwise, this
        // would result in a memory leak over time.
        try await withThrowingDiscardingTaskGroup { group in
            try await channel.executeThenClose { inbound in
                for try await connectionChannel in inbound {

                    group.addTask {
                        await self.handleConnection(channel: connectionChannel, maxInvocations: self.maxInvocations)
                        logger.trace("Done handling connection")
                    }

                    // This mock server only accepts one connection
                    // the Lambda Function Runtime will send multiple requests on that single connection
                    // This Mock Server closes the connection when MAX_INVOCATION is reached
                    break
                }
            }
        }
        // it's ok to keep this at `info` level because it is only used for local testing and unit tests
        logger.info("Server shutting down")
    }

    /// This method handles a single connection by responsing hard coded value to a Lambda function request.
    /// It handles two requests: one for the next invocation and one for the response.
    /// when the maximum number of requests is reached, it closes the connection.
    private func handleConnection(
        channel: NIOAsyncChannel<HTTPServerRequestPart, HTTPServerResponsePart>,
        maxInvocations: Int
    ) async {

        var requestHead: HTTPRequestHead!
        var requestBody: ByteBuffer?

        // each Lambda invocation results in TWO HTTP requests (GET /next and POST /response)
        let maxRequests = maxInvocations * 2
        let requestCount = SharedCounter(maxValue: maxRequests)

        // Note that this method is non-throwing and we are catching any error.
        // We do this since we don't want to tear down the whole server when a single request
        // encounters an error.
        do {
            try await channel.executeThenClose { inbound, outbound in
                for try await inboundData in inbound {
                    let requestNumber = requestCount.current()
                    logger.trace("Handling request", metadata: ["requestNumber": "\(requestNumber)"])

                    if case .head(let head) = inboundData {
                        logger.trace("Received request head", metadata: ["head": "\(head)"])
                        requestHead = head
                    }
                    if case .body(let body) = inboundData {
                        logger.trace("Received request body", metadata: ["body": "\(body)"])
                        requestBody = body
                    }
                    if case .end(let end) = inboundData {
                        logger.trace("Received request end", metadata: ["end": "\(String(describing: end))"])

                        precondition(requestHead != nil, "Received .end without .head")
                        let (responseStatus, responseHeaders, responseBody) = self.processRequest(
                            requestHead: requestHead,
                            requestBody: requestBody
                        )

                        try await self.sendResponse(
                            responseStatus: responseStatus,
                            responseHeaders: responseHeaders,
                            responseBody: responseBody,
                            outbound: outbound
                        )

                        requestHead = nil

                        if requestCount.increment() {
                            logger.info(
                                "Maximum number of requests reached, closing this connection",
                                metadata: ["maxRequest": "\(maxRequests)"]
                            )
                            break  // this finishes handiling request on this connection
                        }
                    }
                }
            }
        } catch {
            logger.error("Hit error: \(error)")
        }
    }
    /// This function process the requests and return an hard-coded response (string or JSON depending on the mode).
    /// We ignore the requestBody.
    private func processRequest(
        requestHead: HTTPRequestHead,
        requestBody: ByteBuffer?
    ) -> (HTTPResponseStatus, [(String, String)], String) {
        var responseStatus: HTTPResponseStatus = .ok
        var responseBody: String = ""
        var responseHeaders: [(String, String)] = []

        logger.trace(
            "Processing request",
            metadata: ["VERB": "\(requestHead.method)", "URI": "\(requestHead.uri)"]
        )

        if requestHead.uri.hasSuffix("/next") {
            responseStatus = .accepted

            let requestId = UUID().uuidString
            switch self.mode {
            case .string:
                responseBody = "\"Seb\""  // must be a valid JSON document
            case .json:
                responseBody = "{ \"name\": \"Seb\", \"age\" : 52 }"
            }
            let deadline = Int64(Date(timeIntervalSinceNow: 60).timeIntervalSince1970 * 1000)
            responseHeaders = [
                (AmazonHeaders.requestID, requestId),
                (AmazonHeaders.invokedFunctionARN, "arn:aws:lambda:us-east-1:123456789012:function:custom-runtime"),
                (AmazonHeaders.traceID, "Root=1-5bef4de7-ad49b0e87f6ef6c87fc2e700;Parent=9a9197af755a6419;Sampled=1"),
                (AmazonHeaders.deadline, String(deadline)),
            ]
        } else if requestHead.uri.hasSuffix("/response") {
            responseStatus = .accepted
        } else if requestHead.uri.hasSuffix("/error") {
            responseStatus = .accepted
        } else {
            responseStatus = .notFound
        }
        logger.trace("Returning response: \(responseStatus), \(responseHeaders), \(responseBody)")
        return (responseStatus, responseHeaders, responseBody)
    }

    private func sendResponse(
        responseStatus: HTTPResponseStatus,
        responseHeaders: [(String, String)],
        responseBody: String,
        outbound: NIOAsyncChannelOutboundWriter<HTTPServerResponsePart>
    ) async throws {
        var headers = HTTPHeaders(responseHeaders)
        headers.add(name: "Content-Length", value: "\(responseBody.utf8.count)")
        headers.add(name: "KeepAlive", value: "timeout=1, max=2")

        logger.trace("Writing response head")
        try await outbound.write(
            HTTPServerResponsePart.head(
                HTTPResponseHead(
                    version: .init(major: 1, minor: 1),  // use HTTP 1.1 it keeps connection alive between requests
                    status: responseStatus,
                    headers: headers
                )
            )
        )
        logger.trace("Writing response body")
        try await outbound.write(HTTPServerResponsePart.body(.byteBuffer(ByteBuffer(string: responseBody))))
        logger.trace("Writing response end")
        try await outbound.write(HTTPServerResponsePart.end(nil))
    }

    private enum Mode: String {
        case string
        case json
    }

    private static func env(_ name: String) -> String? {
        guard let value = getenv(name) else {
            return nil
        }
        return String(cString: value)
    }

    private enum AmazonHeaders {
        static let requestID = "Lambda-Runtime-Aws-Request-Id"
        static let traceID = "Lambda-Runtime-Trace-Id"
        static let clientContext = "X-Amz-Client-Context"
        static let cognitoIdentity = "X-Amz-Cognito-Identity"
        static let deadline = "Lambda-Runtime-Deadline-Ms"
        static let invokedFunctionARN = "Lambda-Runtime-Invoked-Function-Arn"
    }

    private final class SharedCounter: Sendable {
        private let counterMutex = Mutex<Int>(0)
        private let maxValue: Int

        init(maxValue: Int) {
            self.maxValue = maxValue
        }
        func current() -> Int {
            counterMutex.withLock { $0 }
        }
        func increment() -> Bool {
            counterMutex.withLock {
                $0 += 1
                return $0 >= maxValue
            }
        }
    }
}
