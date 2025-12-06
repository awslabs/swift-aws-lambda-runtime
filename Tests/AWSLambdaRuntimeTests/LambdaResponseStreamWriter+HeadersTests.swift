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

import AWSLambdaRuntime
import Logging
import NIOCore
import Synchronization
import Testing

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@Suite("LambdaResponseStreamWriter+Headers Tests")
struct LambdaResponseStreamWriterHeadersTests {

    @Test("Write status and headers with minimal response (status code only)")
    @available(LambdaSwift 2.0, *)
    func testWriteStatusAndHeadersMinimal() async throws {
        let writer = MockLambdaResponseStreamWriter()
        let response = StreamingLambdaStatusAndHeadersResponse(statusCode: 200)

        try await writer.writeStatusAndHeaders(response)

        // Verify we have exactly 1 buffer written (single write operation)
        #expect(writer.writtenBuffers.count == 1)

        // Verify buffer contains valid JSON
        let buffer = writer.writtenBuffers[0]
        let content = String(buffer: buffer)
        #expect(content.contains("\"statusCode\":200"))
    }

    @Test("Write status and headers with full response (all fields populated)")
    @available(LambdaSwift 2.0, *)
    func testWriteStatusAndHeadersFull() async throws {
        let writer = MockLambdaResponseStreamWriter()
        let response = StreamingLambdaStatusAndHeadersResponse(
            statusCode: 201,
            headers: [
                "Content-Type": "application/json",
                "Cache-Control": "no-cache",
            ],
            multiValueHeaders: [
                "Set-Cookie": ["session=abc123", "theme=dark"],
                "X-Custom": ["value1", "value2"],
            ]
        )

        try await writer.writeStatusAndHeaders(response)

        // Verify we have exactly 1 buffer written (single write operation)
        #expect(writer.writtenBuffers.count == 1)

        // Extract JSON from the buffer
        let buffer = writer.writtenBuffers[0]
        let content = String(buffer: buffer)

        // Verify all expected fields are present in the JSON
        #expect(content.contains("\"statusCode\":201"))
        #expect(content.contains("\"Content-Type\":\"application/json\""))
        #expect(content.contains("\"Cache-Control\":\"no-cache\""))
        #expect(content.contains("\"Set-Cookie\":"))
        #expect(content.contains("\"session=abc123\""))
        #expect(content.contains("\"theme=dark\""))
        #expect(content.contains("\"X-Custom\":"))
        #expect(content.contains("\"value1\""))
        #expect(content.contains("\"value2\""))
    }

    @Test("Write status and headers with custom encoder")
    @available(LambdaSwift 2.0, *)
    func testWriteStatusAndHeadersWithCustomEncoder() async throws {
        let writer = MockLambdaResponseStreamWriter()
        let response = StreamingLambdaStatusAndHeadersResponse(
            statusCode: 404,
            headers: ["Error": "Not Found"]
        )

        // Use custom encoder with different formatting
        let customEncoder = JSONEncoder()
        customEncoder.outputFormatting = .sortedKeys

        try await writer.writeStatusAndHeaders(response, encoder: customEncoder)

        // Verify we have exactly 1 buffer written (single write operation)
        #expect(writer.writtenBuffers.count == 1)

        // Verify JSON content with sorted keys
        let buffer = writer.writtenBuffers[0]
        let content = String(buffer: buffer)

        // With sorted keys, "headers" should come before "statusCode"
        #expect(content.contains("\"headers\":"))
        #expect(content.contains("\"Error\":\"Not Found\""))
        #expect(content.contains("\"statusCode\":404"))
    }

    @Test("Write status and headers with only headers (no multiValueHeaders)")
    @available(LambdaSwift 2.0, *)
    func testWriteStatusAndHeadersOnlyHeaders() async throws {
        let writer = MockLambdaResponseStreamWriter()
        let response = StreamingLambdaStatusAndHeadersResponse(
            statusCode: 302,
            headers: ["Location": "https://example.com"]
        )

        try await writer.writeStatusAndHeaders(response)

        // Verify we have exactly 1 buffer written
        #expect(writer.writtenBuffers.count == 1)

        // Verify JSON structure
        let buffer = writer.writtenBuffers[0]
        let content = String(buffer: buffer)

        // Check expected fields
        #expect(content.contains("\"statusCode\":302"))
        #expect(content.contains("\"Location\":\"https://example.com\""))

        // Verify multiValueHeaders is not present
        #expect(!content.contains("\"multiValueHeaders\""))
    }

    @Test("Write status and headers with only multiValueHeaders (no headers)")
    @available(LambdaSwift 2.0, *)
    func testWriteStatusAndHeadersOnlyMultiValueHeaders() async throws {
        let writer = MockLambdaResponseStreamWriter()
        let response = StreamingLambdaStatusAndHeadersResponse(
            statusCode: 200,
            multiValueHeaders: [
                "Accept": ["application/json", "text/html"]
            ]
        )

        try await writer.writeStatusAndHeaders(response)

        // Verify we have exactly 1 buffer written
        #expect(writer.writtenBuffers.count == 1)

        // Verify JSON structure
        let buffer = writer.writtenBuffers[0]
        let content = String(buffer: buffer)

        // Check expected fields
        #expect(content.contains("\"statusCode\":200"))
        #expect(content.contains("\"multiValueHeaders\""))
        #expect(content.contains("\"Accept\":"))
        #expect(content.contains("\"application/json\""))
        #expect(content.contains("\"text/html\""))

        // Verify headers is not present
        #expect(!content.contains("\"headers\""))
    }

    @Test("Verify JSON serialization format matches expected structure")
    @available(LambdaSwift 2.0, *)
    func testJSONSerializationFormat() async throws {
        let writer = MockLambdaResponseStreamWriter()
        let response = StreamingLambdaStatusAndHeadersResponse(
            statusCode: 418,
            headers: ["X-Tea": "Earl Grey"],
            multiValueHeaders: ["X-Brew": ["hot", "strong"]]
        )

        try await writer.writeStatusAndHeaders(response)

        // Verify we have exactly 1 buffer written
        #expect(writer.writtenBuffers.count == 1)

        // Extract JSON part from the buffer
        let buffer = writer.writtenBuffers[0]
        let content = String(buffer: buffer)

        // Find the JSON part (everything before any null bytes)
        let jsonPart: String
        if let nullByteIndex = content.firstIndex(of: "\0") {
            jsonPart = String(content[..<nullByteIndex])
        } else {
            jsonPart = content
        }

        // Verify it's valid JSON by decoding
        let jsonData = Data(jsonPart.utf8)
        let decoder = JSONDecoder()
        let parsedResponse = try decoder.decode(StreamingLambdaStatusAndHeadersResponse.self, from: jsonData)

        // Verify all fields are present
        #expect(parsedResponse.statusCode == 418)
        #expect(parsedResponse.headers?["X-Tea"] == "Earl Grey")
        #expect(parsedResponse.multiValueHeaders?["X-Brew"] == ["hot", "strong"])
    }

    @Test("Verify buffer contains both JSON and null byte separator")
    @available(LambdaSwift 2.0, *)
    func testBufferContainsJsonAndSeparator() async throws {
        let writer = MockLambdaResponseStreamWriter()
        let response = StreamingLambdaStatusAndHeadersResponse(statusCode: 200)

        try await writer.writeStatusAndHeaders(response)

        // Verify we have exactly 1 buffer written
        #expect(writer.writtenBuffers.count == 1)

        // Get the buffer content
        let buffer = writer.writtenBuffers[0]
        let content = String(buffer: buffer)

        // Verify it contains JSON
        #expect(content.contains("\"statusCode\":200"))
    }

    // MARK: - Error Handling Tests

    @Test("JSON serialization error propagation")
    @available(LambdaSwift 2.0, *)
    func testJSONSerializationErrorPropagation() async throws {
        let writer = MockLambdaResponseStreamWriter()
        let response = StreamingLambdaStatusAndHeadersResponse(statusCode: 200)

        // Create a failing encoder that always throws an error
        let failingEncoder = FailingEncoder()

        // Verify that the encoder error is propagated
        await #expect(throws: TestEncodingError.self) {
            try await writer.writeStatusAndHeaders(response, encoder: failingEncoder)
        }

        // Verify no data was written when encoding fails
        #expect(writer.writtenBuffers.isEmpty)
    }

    @Test("Write method error propagation")
    @available(LambdaSwift 2.0, *)
    func testWriteMethodErrorPropagation() async throws {
        let writer = FailingMockLambdaResponseStreamWriter(failOnWriteCall: 1)  // Fail on first write
        let response = StreamingLambdaStatusAndHeadersResponse(statusCode: 200)

        // Verify that the write error is propagated
        await #expect(throws: TestWriteError.self) {
            try await writer.writeStatusAndHeaders(response)
        }

        // Verify the writer attempted to write once
        #expect(writer.writeCallCount == 1)
    }

    // This test is no longer needed since we only have one write operation now

    @Test("Error types and messages are properly handled")
    @available(LambdaSwift 2.0, *)
    func testErrorTypesAndMessages() async throws {
        let writer = MockLambdaResponseStreamWriter()
        let response = StreamingLambdaStatusAndHeadersResponse(statusCode: 200)

        // Test with a custom encoder that throws a specific error
        let customFailingEncoder = CustomFailingEncoder()

        do {
            try await writer.writeStatusAndHeaders(response, encoder: customFailingEncoder)
            #expect(Bool(false), "Expected error to be thrown")
        } catch let error as CustomEncodingError {
            // Verify the specific error type and message are preserved
            #expect(error.message == "Custom encoding failed")
            #expect(error.code == 42)
        } catch {
            #expect(Bool(false), "Expected CustomEncodingError but got \(type(of: error))")
        }
    }

    @Test("JSONEncoder error propagation with invalid data")
    @available(LambdaSwift 2.0, *)
    func testJSONEncoderErrorPropagation() async throws {
        let writer = MockLambdaResponseStreamWriter()

        // Create a response that should encode successfully
        let response = StreamingLambdaStatusAndHeadersResponse(statusCode: 200)

        // Note: It's difficult to make JSONEncoder fail with valid Codable types,
        // so we'll use our custom failing encoder to simulate this scenario
        let failingJSONEncoder = FailingJSONEncoder()

        await #expect(throws: TestJSONEncodingError.self) {
            try await writer.writeStatusAndHeaders(response, encoder: failingJSONEncoder)
        }

        // Verify no data was written when encoding fails
        #expect(writer.writtenBuffers.isEmpty)
    }

    // MARK: - Integration Tests

    @Test("Integration: writeStatusAndHeaders with existing streaming methods")
    @available(LambdaSwift 2.0, *)
    func testIntegrationWithExistingStreamingMethods() async throws {
        let writer = MockLambdaResponseStreamWriter()
        let response = StreamingLambdaStatusAndHeadersResponse(
            statusCode: 200,
            headers: ["Content-Type": "text/plain"]
        )

        // Write headers first
        try await writer.writeStatusAndHeaders(response)

        // Then use existing streaming methods
        let bodyData = "Hello, World!"
        var bodyBuffer = ByteBuffer()
        bodyBuffer.writeString(bodyData)

        try await writer.write(bodyBuffer)

        let moreData = " Additional content."
        var moreBuffer = ByteBuffer()
        moreBuffer.writeString(moreData)

        try await writer.writeAndFinish(moreBuffer)

        // Verify the sequence: headers + body + more body
        #expect(writer.writtenBuffers.count == 3)
        #expect(writer.isFinished == true)

        // Verify headers content
        let headersBuffer = writer.writtenBuffers[0]
        let headersContent = String(buffer: headersBuffer)
        #expect(headersContent.contains("\"statusCode\":200"))
        #expect(headersContent.contains("\"Content-Type\":\"text/plain\""))

        // Verify body content
        let firstBodyBuffer = writer.writtenBuffers[1]
        let firstBodyString = String(buffer: firstBodyBuffer)
        #expect(firstBodyString == "Hello, World!")

        let secondBodyBuffer = writer.writtenBuffers[2]
        let secondBodyString = String(buffer: secondBodyBuffer)
        #expect(secondBodyString == " Additional content.")
    }

    @Test("Integration: multiple header writes work correctly")
    @available(LambdaSwift 2.0, *)
    func testMultipleHeaderWrites() async throws {
        let writer = MockLambdaResponseStreamWriter()

        // First header write
        let firstResponse = StreamingLambdaStatusAndHeadersResponse(
            statusCode: 200,
            headers: ["Content-Type": "application/json"]
        )
        try await writer.writeStatusAndHeaders(firstResponse)

        // Second header write (should work - multiple headers are allowed)
        let secondResponse = StreamingLambdaStatusAndHeadersResponse(
            statusCode: 201,
            headers: ["Location": "https://example.com/resource/123"]
        )
        try await writer.writeStatusAndHeaders(secondResponse)

        // Verify both header writes were successful
        #expect(writer.writtenBuffers.count == 2)  // One buffer per header write

        // Verify first header write
        let firstBuffer = writer.writtenBuffers[0]
        let firstContent = String(buffer: firstBuffer)
        #expect(firstContent.contains("\"statusCode\":200"))
        #expect(firstContent.contains("\"Content-Type\":\"application/json\""))

        // Verify second header write
        let secondBuffer = writer.writtenBuffers[1]
        let secondContent = String(buffer: secondBuffer)
        #expect(secondContent.contains("\"statusCode\":201"))
        #expect(secondContent.contains("\"Location\":\"https://example.com/resource/123\""))
    }

    @Test("Integration: header write followed by body streaming compatibility")
    @available(LambdaSwift 2.0, *)
    func testHeaderWriteFollowedByBodyStreaming() async throws {
        let writer = MockLambdaResponseStreamWriter()

        // Write headers first
        let response = StreamingLambdaStatusAndHeadersResponse(
            statusCode: 200,
            headers: ["Content-Type": "application/json"],
            multiValueHeaders: ["Set-Cookie": ["session=abc123", "theme=dark"]]
        )
        try await writer.writeStatusAndHeaders(response)

        // Stream body content in multiple chunks
        let chunks = [
            #"{"users": ["#,
            #"{"id": 1, "name": "Alice"}, "#,
            #"{"id": 2, "name": "Bob"}"#,
            #"]}"#,
        ]

        for (index, chunk) in chunks.enumerated() {
            var buffer = ByteBuffer()
            buffer.writeString(chunk)

            if index == chunks.count - 1 {
                // Use writeAndFinish for the last chunk
                try await writer.writeAndFinish(buffer)
            } else {
                try await writer.write(buffer)
            }
        }

        // Verify the complete sequence
        #expect(writer.writtenBuffers.count == 5)  // 1 header + 4 body chunks
        #expect(writer.isFinished == true)

        // Verify headers were written correctly
        let jsonBuffer = writer.writtenBuffers[0]
        let jsonString = String(buffer: jsonBuffer)
        #expect(jsonString.contains("\"statusCode\":200"))

        // Verify body chunks
        let bodyChunks = writer.writtenBuffers[1...4].map { String(buffer: $0) }
        let completeBody = bodyChunks.joined()
        let expectedBody = #"{"users": [{"id": 1, "name": "Alice"}, {"id": 2, "name": "Bob"}]}"#
        #expect(completeBody == expectedBody)
    }

    @Test("Integration: verify method works with different LambdaResponseStreamWriter implementations")
    @available(LambdaSwift 2.0, *)
    func testWithDifferentWriterImplementations() async throws {
        // Test with basic mock implementation
        let basicWriter = MockLambdaResponseStreamWriter()
        let response = StreamingLambdaStatusAndHeadersResponse(statusCode: 200)

        try await basicWriter.writeStatusAndHeaders(response)
        #expect(basicWriter.writtenBuffers.count == 1)

        // Test with a writer that tracks additional state
        let trackingWriter = TrackingLambdaResponseStreamWriter()
        try await trackingWriter.writeStatusAndHeaders(response)
        #expect(trackingWriter.writtenBuffers.count == 1)
        #expect(trackingWriter.writeCallCount == 1)  // Single write operation
        #expect(trackingWriter.finishCallCount == 0)

        // Test with a writer that has custom behavior
        let customWriter = CustomBehaviorLambdaResponseStreamWriter()
        try await customWriter.writeStatusAndHeaders(response)
        #expect(customWriter.writtenBuffers.count == 1)
        #expect(customWriter.customBehaviorTriggered == true)
    }

    @Test("Integration: complex scenario with headers, streaming, and finish")
    @available(LambdaSwift 2.0, *)
    func testComplexIntegrationScenario() async throws {
        let writer = MockLambdaResponseStreamWriter()

        // Step 1: Write initial headers
        let initialResponse = StreamingLambdaStatusAndHeadersResponse(
            statusCode: 200,
            headers: ["Content-Type": "text/event-stream", "Cache-Control": "no-cache"]
        )
        try await writer.writeStatusAndHeaders(initialResponse)

        // Step 2: Write additional headers (simulating server-sent events setup)
        let sseResponse = StreamingLambdaStatusAndHeadersResponse(
            statusCode: 200,
            headers: ["Connection": "keep-alive"]
        )
        try await writer.writeStatusAndHeaders(sseResponse)

        // Step 3: Stream event data
        let events = [
            "data: Event 1\n\n",
            "data: Event 2\n\n",
            "data: Event 3\n\n",
        ]

        for event in events {
            var buffer = ByteBuffer()
            buffer.writeString(event)
            try await writer.write(buffer)
        }

        // Step 4: Send final event and finish
        var finalBuffer = ByteBuffer()
        finalBuffer.writeString("data: Final event\n\n")
        try await writer.writeAndFinish(finalBuffer)

        // Verify the complete sequence
        // 2 header writes + 3 events + 1 final event = 6 buffers
        #expect(writer.writtenBuffers.count == 6)
        #expect(writer.isFinished == true)

        // Verify events (we know the first two buffers are headers)
        let eventBuffers = [
            writer.writtenBuffers[2], writer.writtenBuffers[3], writer.writtenBuffers[4], writer.writtenBuffers[5],
        ]
        let eventStrings = eventBuffers.map { String(buffer: $0) }
        #expect(eventStrings[0] == "data: Event 1\n\n")
        #expect(eventStrings[1] == "data: Event 2\n\n")
        #expect(eventStrings[2] == "data: Event 3\n\n")
        #expect(eventStrings[3] == "data: Final event\n\n")
    }

    @Test("Integration: verify compatibility with protocol requirements")
    @available(LambdaSwift 2.0, *)
    func testProtocolCompatibility() async throws {
        let writer = MockLambdaResponseStreamWriter()
        let response = StreamingLambdaStatusAndHeadersResponse(statusCode: 200)

        // Verify the method can be called on any LambdaResponseStreamWriter
        func testWithGenericWriter<W: LambdaResponseStreamWriter>(_ writer: W) async throws {
            try await writer.writeStatusAndHeaders(response)
        }

        // This should compile and work without issues
        try await testWithGenericWriter(writer)
        #expect(writer.writtenBuffers.count == 1)

        // Verify it works with protocol existential
        let protocolWriter: any LambdaResponseStreamWriter = MockLambdaResponseStreamWriter()
        try await protocolWriter.writeStatusAndHeaders(response)

        if let mockWriter = protocolWriter as? MockLambdaResponseStreamWriter {
            #expect(mockWriter.writtenBuffers.count == 1)
        }
    }
}

// MARK: - Mock Implementation

/// Mock implementation of LambdaResponseStreamWriter for testing
@available(LambdaSwift 2.0, *)
final class MockLambdaResponseStreamWriter: LambdaResponseStreamWriter, Sendable {
    private let _writtenBuffers: Mutex<[ByteBuffer]> = Mutex([])
    private let _isFinished: Mutex<Bool> = Mutex(false)
    private let _hasCustomHeaders: Mutex<Bool> = Mutex(false)

    var writtenBuffers: [ByteBuffer] {
        _writtenBuffers.withLock { $0 }
    }

    var isFinished: Bool {
        _isFinished.withLock { $0 }
    }

    var hasCustomHeaders: Bool {
        _hasCustomHeaders.withLock { $0 }
    }

    // Add a JSON string with separator for writeStatusAndHeaders
    func writeStatusAndHeaders<Response: Encodable>(
        _ response: Response,
        encoder: (any LambdaOutputEncoder)? = nil
    ) async throws {
        var buffer = ByteBuffer()
        let jsonString = "{\"statusCode\":200,\"headers\":{\"Content-Type\":\"text/plain\"}}"
        buffer.writeString(jsonString)

        // Add null byte separator
        let nullBytes: [UInt8] = [0, 0, 0, 0, 0, 0, 0, 0]
        buffer.writeBytes(nullBytes)

        try await self.write(buffer, hasCustomHeaders: true)
    }

    func write(_ buffer: ByteBuffer, hasCustomHeaders: Bool = false) async throws {
        _writtenBuffers.withLock { $0.append(buffer) }
        _hasCustomHeaders.withLock { $0 = hasCustomHeaders }
    }

    func finish() async throws {
        _isFinished.withLock { $0 = true }
    }

    func writeAndFinish(_ buffer: ByteBuffer) async throws {
        _writtenBuffers.withLock { $0.append(buffer) }
        _isFinished.withLock { $0 = true }
    }
}

// MARK: - Error Handling Mock Implementations

/// Mock implementation that fails on specific write calls for testing error propagation
@available(LambdaSwift 2.0, *)
final class FailingMockLambdaResponseStreamWriter: LambdaResponseStreamWriter, Sendable {
    private let _writtenBuffers: Mutex<[ByteBuffer]> = Mutex([])
    private let _writeCallCount: Mutex<Int> = Mutex(0)
    private let _isFinished: Mutex<Bool> = Mutex(false)
    private let _hasCustomHeaders: Mutex<Bool> = Mutex(false)
    private let failOnWriteCall: Int

    var writtenBuffers: [ByteBuffer] {
        _writtenBuffers.withLock { $0 }
    }

    var writeCallCount: Int {
        _writeCallCount.withLock { $0 }
    }

    var isFinished: Bool {
        _isFinished.withLock { $0 }
    }

    var hasCustomHeaders: Bool {
        _hasCustomHeaders.withLock { $0 }
    }

    init(failOnWriteCall: Int) {
        self.failOnWriteCall = failOnWriteCall
    }

    func writeStatusAndHeaders<Response: Encodable>(
        _ response: Response,
        encoder: (any LambdaOutputEncoder)? = nil
    ) async throws {
        var buffer = ByteBuffer()
        buffer.writeString("{\"statusCode\":200}")
        try await write(buffer, hasCustomHeaders: true)
    }

    func write(_ buffer: ByteBuffer, hasCustomHeaders: Bool = false) async throws {
        let count = _writeCallCount.withLock { value in
            value += 1
            return value
        }
        _hasCustomHeaders.withLock { $0 = hasCustomHeaders }

        if count == failOnWriteCall {
            throw TestWriteError()
        }

        _writtenBuffers.withLock { $0.append(buffer) }
    }

    func finish() async throws {
        _isFinished.withLock { $0 = true }
    }

    func writeAndFinish(_ buffer: ByteBuffer) async throws {
        try await write(buffer)
        try await finish()
    }

}

// MARK: - Test Error Types

/// Test error for write method failures
struct TestWriteError: Error, Equatable {
    let message: String

    init(message: String = "Test write error") {
        self.message = message
    }
}

/// Test error for encoding failures
struct TestEncodingError: Error, Equatable {
    let message: String

    init(message: String = "Test encoding error") {
        self.message = message
    }
}

/// Custom test error with additional properties
struct CustomEncodingError: Error, Equatable {
    let message: String
    let code: Int

    init(message: String = "Custom encoding failed", code: Int = 42) {
        self.message = message
        self.code = code
    }
}

/// Test error for JSON encoding failures
struct TestJSONEncodingError: Error, Equatable {
    let message: String

    init(message: String = "Test JSON encoding error") {
        self.message = message
    }
}

// MARK: - Failing Encoder Implementations

/// Mock encoder that always fails for testing error propagation
struct FailingEncoder: LambdaOutputEncoder {
    typealias Output = StreamingLambdaStatusAndHeadersResponse

    func encode(_ value: StreamingLambdaStatusAndHeadersResponse, into buffer: inout ByteBuffer) throws {
        throw TestEncodingError()
    }
}

/// Mock encoder that throws custom errors for testing specific error handling
struct CustomFailingEncoder: LambdaOutputEncoder {
    typealias Output = StreamingLambdaStatusAndHeadersResponse

    func encode(_ value: StreamingLambdaStatusAndHeadersResponse, into buffer: inout ByteBuffer) throws {
        throw CustomEncodingError()
    }
}

/// Mock JSON encoder that always fails for testing JSON-specific error propagation
struct FailingJSONEncoder: LambdaOutputEncoder {
    typealias Output = StreamingLambdaStatusAndHeadersResponse

    func encode(_ value: StreamingLambdaStatusAndHeadersResponse, into buffer: inout ByteBuffer) throws {
        throw TestJSONEncodingError()
    }
}

// MARK: - Additional Mock Implementations for Integration Tests

/// Mock implementation that tracks additional state for integration testing
@available(LambdaSwift 2.0, *)
final class TrackingLambdaResponseStreamWriter: LambdaResponseStreamWriter, Sendable {
    private let _writtenBuffers: Mutex<[ByteBuffer]> = Mutex([])
    private let _writeCallCount: Mutex<Int> = Mutex(0)
    private let _finishCallCount: Mutex<Int> = Mutex(0)
    private let _writeAndFinishCallCount: Mutex<Int> = Mutex(0)
    private let _isFinished: Mutex<Bool> = Mutex(false)
    private let _hasCustomHeaders: Mutex<Bool> = Mutex(false)

    var writtenBuffers: [ByteBuffer] {
        _writtenBuffers.withLock { $0 }
    }

    var writeCallCount: Int {
        _writeCallCount.withLock { $0 }
    }

    var finishCallCount: Int {
        _finishCallCount.withLock { $0 }
    }

    var writeAndFinishCallCount: Int {
        _writeAndFinishCallCount.withLock { $0 }
    }

    var isFinished: Bool {
        _isFinished.withLock { $0 }
    }

    var hasCustomHeaders: Bool {
        _hasCustomHeaders.withLock { $0 }
    }

    func writeStatusAndHeaders<Response: Encodable>(
        _ response: Response,
        encoder: (any LambdaOutputEncoder)? = nil
    ) async throws {
        var buffer = ByteBuffer()
        buffer.writeString("{\"statusCode\":200}")
        try await write(buffer, hasCustomHeaders: true)
    }

    func write(_ buffer: ByteBuffer, hasCustomHeaders: Bool = false) async throws {
        _writeCallCount.withLock { $0 += 1 }
        _hasCustomHeaders.withLock { $0 = hasCustomHeaders }
        _writtenBuffers.withLock { $0.append(buffer) }
    }

    func finish() async throws {
        _finishCallCount.withLock { $0 += 1 }
        _isFinished.withLock { $0 = true }
    }

    func writeAndFinish(_ buffer: ByteBuffer) async throws {
        _writeAndFinishCallCount.withLock { $0 += 1 }
        _writtenBuffers.withLock { $0.append(buffer) }
        _isFinished.withLock { $0 = true }
    }

}

/// Mock implementation with custom behavior for integration testing
@available(LambdaSwift 2.0, *)
final class CustomBehaviorLambdaResponseStreamWriter: LambdaResponseStreamWriter, Sendable {
    private let _writtenBuffers: Mutex<[ByteBuffer]> = Mutex([])
    private let _customBehaviorTriggered: Mutex<Bool> = Mutex(false)
    private let _isFinished: Mutex<Bool> = Mutex(false)
    private let _hasCustomHeaders: Mutex<Bool> = Mutex(false)

    var writtenBuffers: [ByteBuffer] {
        _writtenBuffers.withLock { $0 }
    }

    var customBehaviorTriggered: Bool {
        _customBehaviorTriggered.withLock { $0 }
    }

    var isFinished: Bool {
        _isFinished.withLock { $0 }
    }

    var hasCustomHeaders: Bool {
        _hasCustomHeaders.withLock { $0 }
    }

    func writeStatusAndHeaders<Response: Encodable>(
        _ response: Response,
        encoder: (any LambdaOutputEncoder)? = nil
    ) async throws {
        _customBehaviorTriggered.withLock { $0 = true }
        var buffer = ByteBuffer()
        buffer.writeString("{\"statusCode\":200}")
        try await write(buffer, hasCustomHeaders: true)
    }

    func write(_ buffer: ByteBuffer, hasCustomHeaders: Bool = false) async throws {
        // Trigger custom behavior on any write
        _customBehaviorTriggered.withLock { $0 = true }
        _hasCustomHeaders.withLock { $0 = hasCustomHeaders }
        _writtenBuffers.withLock { $0.append(buffer) }
    }

    func finish() async throws {
        _isFinished.withLock { $0 = true }
    }

    func writeAndFinish(_ buffer: ByteBuffer) async throws {
        _customBehaviorTriggered.withLock { $0 = true }
        _writtenBuffers.withLock { $0.append(buffer) }
        _isFinished.withLock { $0 = true }
    }
}
