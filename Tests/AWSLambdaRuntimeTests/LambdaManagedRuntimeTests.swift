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

#if ManagedRuntimeSupport

import Foundation
import Logging
import NIOCore
import Synchronization
import Testing

@testable import AWSLambdaRuntime

@Suite(.serialized)
struct LambdaManagedRuntimeTests {

    // Test 1: Concurrent Handler Execution
    @Test("LambdaManagedRuntime handler handles concurrent invocations")
    @available(LambdaSwift 2.0, *)
    func testConcurrentHandlerExecution() async throws {
        let handler = ConcurrentMockHandler()

        let invocationCount = 5

        let results = try await withThrowingTaskGroup(of: String.self) { group in
            // Simulate concurrent invocations
            for i in 0..<invocationCount {
                group.addTask {
                    let buffer = ByteBuffer(string: "test-\(i)")
                    let writer = MockResponseWriter()
                    let context = LambdaContext.makeTest()

                    var mutableHandler = handler
                    try await mutableHandler.handle(buffer, responseWriter: writer, context: context)

                    return "completed-\(i)"
                }
            }

            var collectedResults: [String] = []
            for try await result in group {
                collectedResults.append(result)
            }
            return collectedResults
        }

        #expect(results.count == invocationCount)
    }

    // Test 2: Sendable Constraint Enforcement (Compilation Test)
    @Test("LambdaManagedRuntime enforces Sendable handler requirements")
    @available(LambdaSwift 2.0, *)
    func testSendableHandlerRequirement() {
        // This test verifies that only Sendable handlers compile
        let sendableHandler = SendableMockHandler()

        // This should compile successfully
        let _ = LambdaManagedRuntime(
            handler: sendableHandler,
            eventLoop: Lambda.defaultEventLoop
        )

        // Non-Sendable handlers would fail at compile time
        // Uncomment to verify compilation failure:
        // let nonSendableHandler = NonSendableMockHandler()
        // let _ = LambdaManagedRuntime(handler: nonSendableHandler) // Should not compile

    }

    // Test 3: Thread-Safe Adapter Tests
    // @Test("Sendable adapters work with concurrent execution")
    // @available(LambdaSwift 2.0, *)
    // func testSendableAdapters() async throws {
    //     let decoder = LambdaJSONEventDecoderSendable(JSONDecoder())
    //     let encoder = LambdaJSONOutputEncoderSendable<String>(JSONEncoder())

    //     let concurrentTasks = 10

    //     let results = try await withThrowingTaskGroup(of: String.self) { group in
    //         for i in 0..<concurrentTasks {
    //             group.addTask {
    //                 // Test concurrent decoding
    //                 let inputBuffer = ByteBuffer(string: #"{"message": "test-\#(i)"}"#)
    //                 let decoded = try decoder.decode(TestEvent.self, from: inputBuffer)

    //                 // Test concurrent encoding
    //                 let output = "response-\(i)"
    //                 var encoded = ByteBuffer()
    //                 try encoder.encode(output, into: &encoded)

    //                 return "\(decoded.message)-\(String(buffer: encoded))"
    //             }
    //         }

    //         var collectedResults: [String] = []
    //         for try await result in group {
    //             collectedResults.append(result)
    //         }
    //         return collectedResults
    //     }

    //     #expect(results.count == concurrentTasks)
    //     #expect(results.allSatisfy { $0.contains("test-") && $0.contains("response-") })
    // }

    // Test 4: Concurrency Level Detection
    @Test("Runtime detects AWS_LAMBDA_MAX_CONCURRENCY configuration")
    @available(LambdaSwift 2.0, *)
    func testConcurrencyLevelDetection() async throws {
        // Test with concurrency = 1 (should behave like traditional runtime)
        setenv("AWS_LAMBDA_MAX_CONCURRENCY", "1", 1)
        defer { unsetenv("AWS_LAMBDA_MAX_CONCURRENCY") }

        #expect(throws: Never.self) {
            let handler = ConcurrentMockHandler()
            let _ = LambdaManagedRuntime(
                handler: handler,
                eventLoop: Lambda.defaultEventLoop,
                logger: Logger(label: "ConcurrencyTest")
            )

            // Test with higher concurrency
            setenv("AWS_LAMBDA_MAX_CONCURRENCY", "8", 1)

            let _ = LambdaManagedRuntime(
                handler: handler,
                eventLoop: Lambda.defaultEventLoop,
                logger: Logger(label: "HighConcurrencyTest")
            )
        }
    }
}

// MARK: - Mock Types

@available(LambdaSwift 2.0, *)
struct ConcurrentMockHandler: StreamingLambdaHandler, Sendable {
    mutating func handle(
        _ event: ByteBuffer,
        responseWriter: some LambdaResponseStreamWriter,
        context: LambdaContext
    ) async throws {
        // Simulate some async work
        try await Task.sleep(for: .milliseconds(10))

        let response = ByteBuffer(string: "processed: \(String(buffer: event))")
        try await responseWriter.writeAndFinish(response)
    }
}

@available(LambdaSwift 2.0, *)
struct SendableMockHandler: StreamingLambdaHandler, Sendable {
    mutating func handle(
        _ event: ByteBuffer,
        responseWriter: some LambdaResponseStreamWriter,
        context: LambdaContext
    ) async throws {
        let response = ByteBuffer(string: "sendable response")
        try await responseWriter.writeAndFinish(response)
    }
}

// Non-Sendable handler for compilation test
@available(LambdaSwift 2.0, *)
struct NonSendableMockHandler: StreamingLambdaHandler {
    var nonSendableProperty = NSMutableArray()  // Not Sendable

    mutating func handle(
        _ event: ByteBuffer,
        responseWriter: some LambdaResponseStreamWriter,
        context: LambdaContext
    ) async throws {
        let response = ByteBuffer(string: "non-sendable response")
        try await responseWriter.writeAndFinish(response)
    }
}

struct TestEvent: Codable {
    let message: String
}

struct MockResponseWriter: LambdaResponseStreamWriter, Sendable {
    func write(_ buffer: ByteBuffer, hasCustomHeaders: Bool = false) async throws {}
    func finish() async throws {}
    func writeAndFinish(_ buffer: ByteBuffer) async throws {}
}

#endif
