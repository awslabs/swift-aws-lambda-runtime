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
import Synchronization
import Testing

@testable import AWSLambdaRuntime
@testable import StreamingCodable

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@Suite("Streaming Codable Lambda Handler Tests")
struct LambdaStreamingFromEventTests {

    // MARK: - Test Data Structures

    struct TestEvent: Decodable, Equatable {
        let message: String
        let count: Int
        let delay: Int?
    }

    struct SimpleEvent: Decodable, Equatable {
        let value: String
    }

    // MARK: - Mock Response Writer

    actor MockResponseWriter: LambdaResponseStreamWriter {
        private var writtenBuffers: [ByteBuffer] = []
        private var isFinished = false
        private var writeAndFinishCalled = false

        func write(_ buffer: ByteBuffer, hasCustomHeaders: Bool = false) async throws {
            guard !isFinished else {
                throw MockError.writeAfterFinish
            }
            writtenBuffers.append(buffer)
        }

        func finish() async throws {
            guard !isFinished else {
                throw MockError.alreadyFinished
            }
            isFinished = true
        }

        func writeAndFinish(_ buffer: ByteBuffer) async throws {
            try await write(buffer)
            try await finish()
            writeAndFinishCalled = true
        }

        // Test helpers
        func getWrittenData() -> [String] {
            writtenBuffers.compactMap { buffer in
                buffer.getString(at: buffer.readerIndex, length: buffer.readableBytes)
            }
        }

        func getFinished() -> Bool {
            isFinished
        }

        func getWriteAndFinishCalled() -> Bool {
            writeAndFinishCalled
        }
    }

    enum MockError: Error {
        case writeAfterFinish
        case alreadyFinished
        case decodingFailed
        case handlerError
    }

    // MARK: - Test StreamingFromEventClosureHandler

    @Test("StreamingFromEventClosureHandler handles decoded events correctly")
    func testStreamingFromEventClosureHandler() async throws {
        let responseWriter = MockResponseWriter()
        let context = LambdaContext.makeTest()

        let handler = StreamingFromEventClosureHandler<TestEvent> { event, writer, context in
            let message = "Received: \(event.message) (count: \(event.count))"
            try await writer.writeAndFinish(ByteBuffer(string: message))
        }

        let testEvent = TestEvent(message: "Hello", count: 42, delay: nil)

        try await handler.handle(testEvent, responseWriter: responseWriter, context: context)

        let writtenData = await responseWriter.getWrittenData()
        let isFinished = await responseWriter.getFinished()

        #expect(writtenData == ["Received: Hello (count: 42)"])
        #expect(isFinished == true)
    }

    @Test("StreamingFromEventClosureHandler can stream multiple responses")
    func testStreamingMultipleResponses() async throws {
        let responseWriter = MockResponseWriter()
        let context = LambdaContext.makeTest()

        let handler = StreamingFromEventClosureHandler<TestEvent> { event, writer, context in
            for i in 1...event.count {
                try await writer.write(ByteBuffer(string: "\(i): \(event.message)\n"))
            }
            try await writer.finish()
        }

        let testEvent = TestEvent(message: "Test", count: 3, delay: nil)

        try await handler.handle(testEvent, responseWriter: responseWriter, context: context)

        let writtenData = await responseWriter.getWrittenData()
        let isFinished = await responseWriter.getFinished()

        #expect(writtenData == ["1: Test\n", "2: Test\n", "3: Test\n"])
        #expect(isFinished == true)
    }

    // MARK: - Test StreamingLambdaCodableAdapter

    @Test("StreamingLambdaCodableAdapter decodes JSON and calls handler")
    func testStreamingLambdaCodableAdapter() async throws {
        let responseWriter = MockResponseWriter()
        let context = LambdaContext.makeTest()

        let closureHandler = StreamingFromEventClosureHandler<SimpleEvent> { event, writer, context in
            try await writer.writeAndFinish(ByteBuffer(string: "Echo: \(event.value)"))
        }

        var adapter = StreamingLambdaCodableAdapter(
            decoder: LambdaJSONEventDecoder(JSONDecoder()),
            handler: closureHandler
        )

        let jsonData = #"{"value": "test message"}"#
        let inputBuffer = ByteBuffer(string: jsonData)

        try await adapter.handle(inputBuffer, responseWriter: responseWriter, context: context)

        let writtenData = await responseWriter.getWrittenData()
        let isFinished = await responseWriter.getFinished()

        #expect(writtenData == ["Echo: test message"])
        #expect(isFinished == true)
    }

    @Test("StreamingLambdaCodableAdapter handles JSON decoding errors")
    func testStreamingLambdaCodableAdapterDecodingError() async throws {
        let responseWriter = MockResponseWriter()
        let context = LambdaContext.makeTest()

        let closureHandler = StreamingFromEventClosureHandler<SimpleEvent> { event, writer, context in
            try await writer.writeAndFinish(ByteBuffer(string: "Should not reach here"))
        }

        var adapter = StreamingLambdaCodableAdapter(
            decoder: LambdaJSONEventDecoder(JSONDecoder()),
            handler: closureHandler
        )

        let invalidJsonData = #"{"invalid": "json structure"}"#
        let inputBuffer = ByteBuffer(string: invalidJsonData)

        await #expect(throws: DecodingError.self) {
            try await adapter.handle(inputBuffer, responseWriter: responseWriter, context: context)
        }

        let writtenData = await responseWriter.getWrittenData()
        #expect(writtenData.isEmpty)
    }

    @Test("StreamingLambdaCodableAdapter with convenience JSON initializer")
    func testStreamingLambdaCodableAdapterJSONConvenience() async throws {
        let responseWriter = MockResponseWriter()
        let context = LambdaContext.makeTest()

        let closureHandler = StreamingFromEventClosureHandler<TestEvent> { event, writer, context in
            try await writer.write(ByteBuffer(string: "Message: \(event.message)\n"))
            try await writer.write(ByteBuffer(string: "Count: \(event.count)\n"))
            try await writer.finish()
        }

        var adapter = StreamingLambdaCodableAdapter(handler: closureHandler)

        let jsonData = #"{"message": "Hello World", "count": 5, "delay": 100}"#
        let inputBuffer = ByteBuffer(string: jsonData)

        try await adapter.handle(inputBuffer, responseWriter: responseWriter, context: context)

        let writtenData = await responseWriter.getWrittenData()
        let isFinished = await responseWriter.getFinished()

        #expect(writtenData == ["Message: Hello World\n", "Count: 5\n"])
        #expect(isFinished == true)
    }

    // MARK: - Test Error Handling

    @Test("Handler errors are properly propagated")
    func testHandlerErrorPropagation() async throws {
        let responseWriter = MockResponseWriter()
        let context = LambdaContext.makeTest()

        let closureHandler = StreamingFromEventClosureHandler<SimpleEvent> { event, writer, context in
            throw MockError.handlerError
        }

        var adapter = StreamingLambdaCodableAdapter(
            decoder: LambdaJSONEventDecoder(JSONDecoder()),
            handler: closureHandler
        )

        let jsonData = #"{"value": "test"}"#
        let inputBuffer = ByteBuffer(string: jsonData)

        await #expect(throws: MockError.self) {
            try await adapter.handle(inputBuffer, responseWriter: responseWriter, context: context)
        }
    }

    // MARK: - Test Custom Handler Implementation

    struct CustomStreamingHandler: StreamingLambdaHandlerWithEvent {
        typealias Event = TestEvent

        func handle(
            _ event: Event,
            responseWriter: some LambdaResponseStreamWriter,
            context: LambdaContext
        ) async throws {
            context.logger.trace("Processing event with message: \(event.message)")

            let response = "Processed: \(event.message) with count \(event.count)"
            try await responseWriter.writeAndFinish(ByteBuffer(string: response))
        }
    }

    @Test("Custom StreamingLambdaHandlerWithEvent implementation works")
    func testCustomStreamingHandler() async throws {
        let responseWriter = MockResponseWriter()
        let context = LambdaContext.makeTest()

        let handler = CustomStreamingHandler()
        let testEvent = TestEvent(message: "Custom Handler Test", count: 10, delay: nil)

        try await handler.handle(testEvent, responseWriter: responseWriter, context: context)

        let writtenData = await responseWriter.getWrittenData()
        let isFinished = await responseWriter.getFinished()

        #expect(writtenData == ["Processed: Custom Handler Test with count 10"])
        #expect(isFinished == true)
    }

    @Test("Custom handler with adapter works end-to-end")
    func testCustomHandlerWithAdapter() async throws {
        let responseWriter = MockResponseWriter()
        let context = LambdaContext.makeTest()

        let customHandler = CustomStreamingHandler()
        var adapter = StreamingLambdaCodableAdapter(handler: customHandler)

        let jsonData = #"{"message": "End-to-end test", "count": 7}"#
        let inputBuffer = ByteBuffer(string: jsonData)

        try await adapter.handle(inputBuffer, responseWriter: responseWriter, context: context)

        let writtenData = await responseWriter.getWrittenData()
        let isFinished = await responseWriter.getFinished()

        #expect(writtenData == ["Processed: End-to-end test with count 7"])
        #expect(isFinished == true)
    }

    // MARK: - Test Background Work Simulation

    @Test("Handler can perform background work after streaming")
    func testBackgroundWorkAfterStreaming() async throws {
        let responseWriter = MockResponseWriter()
        let context = LambdaContext.makeTest()

        let backgroundWorkCompleted = Atomic<Bool>(false)

        let handler = StreamingFromEventClosureHandler<SimpleEvent> { event, writer, context in
            // Send response first
            try await writer.writeAndFinish(ByteBuffer(string: "Response: \(event.value)"))

            // Simulate background work
            try await Task.sleep(for: .milliseconds(10))
            backgroundWorkCompleted.store(true, ordering: .relaxed)
        }

        let testEvent = SimpleEvent(value: "background test")

        try await handler.handle(testEvent, responseWriter: responseWriter, context: context)

        let writtenData = await responseWriter.getWrittenData()
        let isFinished = await responseWriter.getFinished()
        let writeAndFinishCalled = await responseWriter.getWriteAndFinishCalled()

        #expect(writtenData == ["Response: background test"])
        #expect(isFinished == true)
        #expect(writeAndFinishCalled == true)
        #expect(backgroundWorkCompleted.load(ordering: .relaxed) == true)
    }
}

// MARK: - Test Helpers

extension LambdaContext {
    static func makeTest() -> LambdaContext {
        LambdaContext.__forTestsOnly(
            requestID: "test-request-id",
            traceID: "test-trace-id",
            invokedFunctionARN: "arn:aws:lambda:us-east-1:123456789012:function:test",
            timeout: .seconds(30),
            logger: Logger(label: "MockedLambdaContext")
        )
    }
}
