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
import Testing

import struct Foundation.UUID

@testable import AWSLambdaRuntime

@Suite
struct LambdaRuntimeClientTests {

    let logger = {
        var logger = Logger(label: "NewLambdaClientRuntimeTest")
        // Uncomment the line below to enable trace-level logging for debugging purposes.
        // logger.logLevel = .trace
        return logger
    }()

    @Test
    @available(LambdaSwift 2.0, *)
    func testSimpleInvocations() async throws {
        struct HappyBehavior: LambdaServerBehavior {
            let requestId = UUID().uuidString
            let event = "hello"

            func getInvocation() -> GetInvocationResult {
                .success((self.requestId, self.event))
            }

            func processResponse(requestId: String, response: String?) -> Result<String?, ProcessResponseError> {
                #expect(self.requestId == requestId)
                #expect(self.event == response)
                return .success(nil)
            }

            func processError(requestId: String, error: ErrorResponse) -> Result<Void, ProcessErrorError> {
                Issue.record("should not report error")
                return .failure(.internalServerError)
            }

            func processInitError(error: ErrorResponse) -> Result<Void, ProcessErrorError> {
                Issue.record("should not report init error")
                return .failure(.internalServerError)
            }
        }

        try await withMockServer(behaviour: HappyBehavior()) { port in
            let configuration = LambdaRuntimeClient.Configuration(ip: "127.0.0.1", port: port)

            try await LambdaRuntimeClient.withRuntimeClient(
                configuration: configuration,
                eventLoop: NIOSingletons.posixEventLoopGroup.next(),
                logger: self.logger
            ) { runtimeClient in
                do {
                    let (invocation, writer) = try await runtimeClient.nextInvocation()
                    let expected = ByteBuffer(string: "hello")
                    #expect(invocation.event == expected)
                    try await writer.writeAndFinish(expected)
                }

                do {
                    let (invocation, writer) = try await runtimeClient.nextInvocation()
                    let expected = ByteBuffer(string: "hello")
                    #expect(invocation.event == expected)
                    try await writer.write(ByteBuffer(string: "h"))
                    try await writer.write(ByteBuffer(string: "e"))
                    try await writer.write(ByteBuffer(string: "l"))
                    try await writer.write(ByteBuffer(string: "l"))
                    try await writer.write(ByteBuffer(string: "o"))
                    try await writer.finish()
                }
            }
        }
    }

    struct StreamingBehavior: LambdaServerBehavior {
        let requestId = UUID().uuidString
        let event = "hello"
        let customHeaders: Bool

        init(customHeaders: Bool = false) {
            self.customHeaders = customHeaders
        }

        func getInvocation() -> GetInvocationResult {
            .success((self.requestId, self.event))
        }

        func processResponse(requestId: String, response: String?) -> Result<String?, ProcessResponseError> {
            #expect(self.requestId == requestId)
            return .success(nil)
        }

        mutating func captureHeaders(_ headers: HTTPHeaders) {
            if customHeaders {
                #expect(headers["Content-Type"].first == "application/vnd.awslambda.http-integration-response")
            }
            #expect(headers["Lambda-Runtime-Function-Response-Mode"].first == "streaming")
            #expect(headers["Trailer"].first?.contains("Lambda-Runtime-Function-Error-Type") == true)
        }

        func processError(requestId: String, error: ErrorResponse) -> Result<Void, ProcessErrorError> {
            Issue.record("should not report error")
            return .failure(.internalServerError)
        }

        func processInitError(error: ErrorResponse) -> Result<Void, ProcessErrorError> {
            Issue.record("should not report init error")
            return .failure(.internalServerError)
        }
    }

    @Test
    @available(LambdaSwift 2.0, *)
    func testStreamingResponseHeaders() async throws {

        let behavior = StreamingBehavior()
        try await withMockServer(behaviour: behavior) { port in
            let configuration = LambdaRuntimeClient.Configuration(ip: "127.0.0.1", port: port)

            try await LambdaRuntimeClient.withRuntimeClient(
                configuration: configuration,
                eventLoop: NIOSingletons.posixEventLoopGroup.next(),
                logger: self.logger
            ) { runtimeClient in
                let (_, writer) = try await runtimeClient.nextInvocation()

                // Start streaming response
                try await writer.write(ByteBuffer(string: "streaming"))

                // Complete the response
                try await writer.finish()

                // Verify headers were set correctly for streaming mode
                // this is done in the behavior's captureHeaders method
            }
        }
    }

    @Test
    @available(LambdaSwift 2.0, *)
    func testStreamingResponseHeadersWithCustomStatus() async throws {

        let behavior = StreamingBehavior(customHeaders: true)
        try await withMockServer(behaviour: behavior) { port in
            let configuration = LambdaRuntimeClient.Configuration(ip: "127.0.0.1", port: port)

            try await LambdaRuntimeClient.withRuntimeClient(
                configuration: configuration,
                eventLoop: NIOSingletons.posixEventLoopGroup.next(),
                logger: self.logger
            ) { runtimeClient in
                let (_, writer) = try await runtimeClient.nextInvocation()

                try await writer.writeStatusAndHeaders(
                    StreamingLambdaStatusAndHeadersResponse(
                        statusCode: 418,  // I'm a tea pot
                        headers: [
                            "Content-Type": "text/plain",
                            "x-my-custom-header": "streaming-example",
                        ]
                    )
                )
                // Start streaming response
                try await writer.write(ByteBuffer(string: "streaming"))

                // Complete the response
                try await writer.finish()

                // Verify headers were set correctly for streaming mode
                // this is done in the behavior's captureHeaders method
            }
        }
    }

    @Test
    @available(LambdaSwift 2.0, *)
    func testRuntimeClientCancellation() async throws {
        struct HappyBehavior: LambdaServerBehavior {
            let requestId = UUID().uuidString
            let event = "hello"

            func getInvocation() -> GetInvocationResult {
                .success((self.requestId, self.event))
            }

            func processResponse(requestId: String, response: String?) -> Result<String?, ProcessResponseError> {
                #expect(self.requestId == requestId)
                #expect(self.event == response)
                return .success(nil)
            }

            func processError(requestId: String, error: ErrorResponse) -> Result<Void, ProcessErrorError> {
                Issue.record("should not report error")
                return .failure(.internalServerError)
            }

            func processInitError(error: ErrorResponse) -> Result<Void, ProcessErrorError> {
                Issue.record("should not report init error")
                return .failure(.internalServerError)
            }
        }

        try await withMockServer(behaviour: HappyBehavior()) { port in
            try await LambdaRuntimeClient.withRuntimeClient(
                configuration: .init(ip: "127.0.0.1", port: port),
                eventLoop: NIOSingletons.posixEventLoopGroup.next(),
                logger: self.logger
            ) { runtimeClient in
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        while true {
                            let (_, writer) = try await runtimeClient.nextInvocation()
                            // Wrap this is a task so cancellation isn't propagated to the write calls
                            try await Task {
                                try await writer.write(ByteBuffer(string: "hello"))
                                try await writer.finish()
                            }.value
                        }
                    }
                    // wait a small amount to ensure we are waiting for continuation
                    try await Task.sleep(for: .milliseconds(100))
                    group.cancelAll()
                }
            }
        }
    }

    struct DisconnectAfterSendingResponseBehavior: LambdaServerBehavior {
        func getInvocation() -> GetInvocationResult {
            .success((UUID().uuidString, "hello"))
        }

        func processResponse(requestId: String, response: String?) -> Result<String?, ProcessResponseError> {
            // Return "delayed-disconnect" to trigger server closing the connection
            // after having accepted the first response
            .success("delayed-disconnect")
        }

        func processError(requestId: String, error: ErrorResponse) -> Result<Void, ProcessErrorError> {
            Issue.record("should not report error")
            return .failure(.internalServerError)
        }

        func processInitError(error: ErrorResponse) -> Result<Void, ProcessErrorError> {
            Issue.record("should not report init error")
            return .failure(.internalServerError)
        }
    }

    struct DisconnectBehavior: LambdaServerBehavior {
        func getInvocation() -> GetInvocationResult {
            .success(("disconnect", "0"))
        }

        func processResponse(requestId: String, response: String?) -> Result<String?, ProcessResponseError> {
            .success(nil)
        }

        func processError(requestId: String, error: ErrorResponse) -> Result<Void, ProcessErrorError> {
            Issue.record("should not report error")
            return .failure(.internalServerError)
        }

        func processInitError(error: ErrorResponse) -> Result<Void, ProcessErrorError> {
            Issue.record("should not report init error")
            return .failure(.internalServerError)
        }
    }

    @Test(
        "Server closing the connection when waiting for next invocation throws an error",
        arguments: [DisconnectBehavior(), DisconnectAfterSendingResponseBehavior()] as [any LambdaServerBehavior]
    )
    @available(LambdaSwift 2.0, *)
    func testChannelCloseFutureWithWaitingForNextInvocation(behavior: any LambdaServerBehavior) async throws {
        try await withMockServer(behaviour: behavior) { port in
            let configuration = LambdaRuntimeClient.Configuration(ip: "127.0.0.1", port: port)

            try await LambdaRuntimeClient.withRuntimeClient(
                configuration: configuration,
                eventLoop: NIOSingletons.posixEventLoopGroup.next(),
                logger: self.logger
            ) { runtimeClient in
                do {

                    // simulate traffic until the server reports it has closed the connection
                    // or a timeout, whichever comes first
                    // result is ignored here, either there is a connection error or a timeout
                    let _ = try await withTimeout(deadline: .seconds(1)) {
                        while true {
                            let (_, writer) = try await runtimeClient.nextInvocation()
                            try await writer.writeAndFinish(ByteBuffer(string: "hello"))
                        }
                    }
                    // result is ignored here, we should never reach this line
                    Issue.record("Connection reset test did not throw an error")

                } catch is CancellationError {
                    Issue.record("Runtime client did not send connection closed error")
                } catch let error as LambdaRuntimeError {
                    logger.trace("LambdaRuntimeError - expected")
                    #expect(error.code == .connectionToControlPlaneLost)
                } catch let error as ChannelError {
                    logger.trace("ChannelError - expected")
                    #expect(error == .ioOnClosedChannel)
                } catch let error as IOError {
                    logger.trace("IOError - expected")
                    #expect(error.errnoCode == ECONNRESET || error.errnoCode == EPIPE)
                } catch {
                    Issue.record("Unexpected error type: \(error)")
                }
            }
        }
    }

    @Test(
        "reportError() sends the correct errorType for different Error types"
    )
    @available(LambdaSwift 2.0, *)
    func testReportErrorReturnsProperErrorType() async throws {
        // Custom error types for testing
        struct MyCustomError: Error {
            let message: String
        }

        enum MyEnumError: Error {
            case anotherCase(String)
        }

        struct ErrorReportingBehavior: LambdaServerBehavior {
            let requestId = UUID().uuidString
            let event = "error-testing"
            let expectedErrorType: String

            func getInvocation() -> GetInvocationResult {
                .success((self.requestId, self.event))
            }

            func processResponse(requestId: String, response: String?) -> Result<String?, ProcessResponseError> {
                Issue.record("should not process response, expecting error report")
                return .failure(.internalServerError)
            }

            func processError(requestId: String, error: ErrorResponse) -> Result<Void, ProcessErrorError> {
                #expect(self.requestId == requestId)
                #expect(
                    error.errorType == self.expectedErrorType,
                    "Expected errorType '\(self.expectedErrorType)' but got '\(error.errorType)'"
                )
                return .success(())
            }

            func processInitError(error: ErrorResponse) -> Result<Void, ProcessErrorError> {
                Issue.record("should not report init error")
                return .failure(.internalServerError)
            }
        }

        // Test with MyCustomError
        try await withMockServer(behaviour: ErrorReportingBehavior(expectedErrorType: "MyCustomError")) { port in
            let configuration = LambdaRuntimeClient.Configuration(ip: "127.0.0.1", port: port)

            try await LambdaRuntimeClient.withRuntimeClient(
                configuration: configuration,
                eventLoop: NIOSingletons.posixEventLoopGroup.next(),
                logger: self.logger
            ) { runtimeClient in
                let (_, writer) = try await runtimeClient.nextInvocation()
                let error = MyCustomError(message: "Something went wrong")
                try await writer.reportError(error)
            }
        }

        // Test with MyEnumError
        try await withMockServer(behaviour: ErrorReportingBehavior(expectedErrorType: "MyEnumError")) { port in
            let configuration = LambdaRuntimeClient.Configuration(ip: "127.0.0.1", port: port)

            try await LambdaRuntimeClient.withRuntimeClient(
                configuration: configuration,
                eventLoop: NIOSingletons.posixEventLoopGroup.next(),
                logger: self.logger
            ) { runtimeClient in
                let (_, writer) = try await runtimeClient.nextInvocation()
                let error = MyEnumError.anotherCase("test")
                try await writer.reportError(error)
            }
        }
    }
}
