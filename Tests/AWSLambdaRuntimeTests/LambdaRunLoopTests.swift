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
import Testing

@testable import AWSLambdaRuntime

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@Suite
struct LambdaRunLoopTests {
    @available(LambdaSwift 2.0, *)
    struct MockEchoHandler: StreamingLambdaHandler {
        func handle(
            _ event: ByteBuffer,
            responseWriter: some LambdaResponseStreamWriter,
            context: LambdaContext
        ) async throws {
            context.logger.info("Test")
            try await responseWriter.writeAndFinish(event)
        }
    }

    @available(LambdaSwift 2.0, *)
    struct FailingHandler: StreamingLambdaHandler {
        func handle(
            _ event: ByteBuffer,
            responseWriter: some LambdaResponseStreamWriter,
            context: LambdaContext
        ) async throws {
            context.logger.info("Test")
            throw LambdaError.handlerError
        }
    }

    @Test
    @available(LambdaSwift 2.0, *)
    func testRunLoop() async throws {
        let mockClient = MockLambdaClient()
        let mockEchoHandler = MockEchoHandler()
        let inputEvent = ByteBuffer(string: "Test Invocation Event")

        try await withThrowingTaskGroup(of: Void.self) { group in
            let logStore = CollectEverythingLogHandler.LogStore()
            let logger = Logger(
                label: "RunLoopTest",
                factory: { _ in CollectEverythingLogHandler(logStore: logStore) }
            )
            group.addTask {
                try await Lambda.runLoop(
                    runtimeClient: mockClient,
                    handler: mockEchoHandler,
                    loggingConfiguration: LoggingConfiguration(logger: logger),
                    logger: logger,
                    isSingleConcurrencyMode: true
                )
            }

            let requestID = UUID().uuidString
            let response = try await mockClient.invoke(event: inputEvent, requestID: requestID)
            #expect(response == inputEvent)
            logStore.assertContainsLog("Test", ("aws-request-id", .exactMatch(requestID)))

            group.cancelAll()
        }
    }

    @Test
    @available(LambdaSwift 2.0, *)
    func testRunLoopError() async throws {
        let mockClient = MockLambdaClient()
        let failingHandler = FailingHandler()
        let inputEvent = ByteBuffer(string: "Test Invocation Event")

        await withThrowingTaskGroup(of: Void.self) { group in
            let logStore = CollectEverythingLogHandler.LogStore()
            let logger = Logger(
                label: "RunLoopTest",
                factory: { _ in CollectEverythingLogHandler(logStore: logStore) }
            )
            group.addTask {
                try await Lambda.runLoop(
                    runtimeClient: mockClient,
                    handler: failingHandler,
                    loggingConfiguration: LoggingConfiguration(logger: logger),
                    logger: logger,
                    isSingleConcurrencyMode: true
                )
            }

            let requestID = UUID().uuidString
            await #expect(
                throws: LambdaError.handlerError,
                performing: {
                    try await mockClient.invoke(event: inputEvent, requestID: requestID)
                }
            )
            logStore.assertContainsLog("Test", ("aws-request-id", .exactMatch(requestID)))

            group.cancelAll()
        }
    }
}
