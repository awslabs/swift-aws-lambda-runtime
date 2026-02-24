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
import Testing

@testable import AWSLambdaRuntime

#if canImport(Darwin)
import Darwin.C
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@Suite
struct JSONLogHandlerTests {

    // MARK: - Helpers

    /// Decodable mirror of LogEntry for test assertions.
    private struct TestLogEntry: Decodable {
        let timestamp: String
        let level: String
        let message: String
        let requestId: String
        let traceId: String
        let file: String?
        let function: String?
        let line: UInt?
        let metadata: [String: String]?
    }

    /// Creates a LogEntry and encodes it, returning the decoded TestLogEntry for assertions.
    @available(LambdaSwift 2.0, *)
    private func makeAndEncode(
        level: Logger.Level = .info,
        message: String = "test",
        requestID: String = "req-1",
        traceID: String = "trace-1",
        file: String = "TestFile.swift",
        function: String = "testFunction()",
        line: UInt = 1,
        handlerMetadata: Logger.Metadata = [:],
        callMetadata: Logger.Metadata? = nil
    ) -> (entry: TestLogEntry?, rawJSON: String?) {
        // Merge metadata the same way the handler does
        var allMetadata = handlerMetadata
        if let callMetadata {
            allMetadata.merge(callMetadata) { _, new in new }
        }

        let logEntry = JSONLogHandler.LogEntry(
            timestamp: Date(),
            level: JSONLogHandler.mapLogLevel(level),
            message: message,
            requestId: requestID,
            traceId: traceID,
            file: file,
            function: function,
            line: line,
            metadata: allMetadata.isEmpty ? nil : allMetadata.mapValues { $0.description }
        )

        guard let data = JSONLogHandler.encodeLogEntry(logEntry) else {
            return (nil, nil)
        }

        let rawJSON = String(data: data, encoding: .utf8)
        let decoded = try? JSONDecoder().decode(TestLogEntry.self, from: data)
        return (decoded, rawJSON)
    }

    // MARK: - JSON Structure

    @Test("Encoded log entry contains all expected fields")
    @available(LambdaSwift 2.0, *)
    func wellFormedJSON() {
        let (entry, rawJSON) = makeAndEncode(
            message: "hello world",
            requestID: "req-abc",
            traceID: "trace-xyz"
        )

        #expect(rawJSON != nil, "Encoding should produce valid JSON")
        #expect(entry != nil, "JSON should decode back to TestLogEntry")
        #expect(entry?.timestamp.isEmpty == false)
        #expect(entry?.level == "INFO")
        #expect(entry?.message == "hello world")
        #expect(entry?.requestId == "req-abc")
        #expect(entry?.traceId == "trace-xyz")
    }

    // MARK: - Log Level Mapping

    @Test("Log levels are mapped correctly to AWS Lambda level strings")
    @available(LambdaSwift 2.0, *)
    func logLevelMapping() {
        let cases: [(Logger.Level, String)] = [
            (.trace, "TRACE"),
            (.debug, "DEBUG"),
            (.info, "INFO"),
            (.notice, "INFO"),
            (.warning, "WARN"),
            (.error, "ERROR"),
            (.critical, "FATAL"),
        ]

        for (level, expected) in cases {
            let mapped = JSONLogHandler.mapLogLevel(level)
            #expect(mapped == expected, "Expected \(level) to map to \(expected)")
        }
    }

    // MARK: - Metadata

    @Test("Per-call metadata is included in encoded output")
    @available(LambdaSwift 2.0, *)
    func perCallMetadata() {
        let (entry, _) = makeAndEncode(callMetadata: ["key1": "value1", "key2": "value2"])

        #expect(entry?.metadata?["key1"] == "value1")
        #expect(entry?.metadata?["key2"] == "value2")
    }

    @Test("Handler-level metadata is included in encoded output")
    @available(LambdaSwift 2.0, *)
    func handlerLevelMetadata() {
        let (entry, _) = makeAndEncode(handlerMetadata: ["persistent": "yes"])

        #expect(entry?.metadata?["persistent"] == "yes")
    }

    @Test("Per-call metadata overrides handler-level metadata for same key")
    @available(LambdaSwift 2.0, *)
    func metadataMergeOverride() {
        let (entry, _) = makeAndEncode(
            handlerMetadata: ["key": "old"],
            callMetadata: ["key": "new"]
        )

        #expect(entry?.metadata?["key"] == "new")
    }

    @Test("Metadata field is nil when no metadata is provided")
    @available(LambdaSwift 2.0, *)
    func noMetadataField() {
        let (entry, _) = makeAndEncode()

        #expect(entry?.metadata == nil)
    }

    // MARK: - Request ID and Trace ID

    @Test("requestID and traceID are correctly encoded")
    @available(LambdaSwift 2.0, *)
    func requestAndTraceIDs() {
        let (entry, _) = makeAndEncode(
            requestID: "550e8400-e29b-41d4-a716-446655440000",
            traceID: "Root=1-5e1b4151-43a0913a12345678901234567"
        )

        #expect(entry?.requestId == "550e8400-e29b-41d4-a716-446655440000")
        #expect(entry?.traceId == "Root=1-5e1b4151-43a0913a12345678901234567")
    }

    // MARK: - Source Location

    @Test("Log entry includes file, function, and line")
    @available(LambdaSwift 2.0, *)
    func sourceLocation() {
        let (entry, _) = makeAndEncode(
            file: "Sources/MyLambda/Handler.swift",
            function: "handle(_:context:)",
            line: 42
        )

        #expect(entry?.file == "Sources/MyLambda/Handler.swift")
        #expect(entry?.function == "handle(_:context:)")
        #expect(entry?.line == 42)
    }

    // MARK: - Timestamp

    @Test("Timestamp is in ISO 8601 format")
    @available(LambdaSwift 2.0, *)
    func iso8601Timestamp() {
        let (entry, _) = makeAndEncode()
        let timestamp = entry?.timestamp
        #expect(timestamp != nil)

        // Verify it matches ISO 8601 format with milliseconds (e.g. "2024-01-16T10:30:45.123Z")
        let iso8601Pattern = #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{1,6}Z$"#
        let matches = timestamp?.range(of: iso8601Pattern, options: .regularExpression) != nil
        #expect(matches, "Timestamp '\(timestamp ?? "")' should be in ISO 8601 format with fractional seconds")
    }

    // MARK: - Metadata subscript

    @Test("Metadata subscript get and set work correctly")
    @available(LambdaSwift 2.0, *)
    func metadataSubscript() {
        var handler = JSONLogHandler(label: "test", requestID: "r", traceID: "t")

        #expect(handler[metadataKey: "foo"] == nil)

        handler[metadataKey: "foo"] = "bar"
        #expect(handler[metadataKey: "foo"] == "bar")

        handler[metadataKey: "foo"] = nil
        #expect(handler[metadataKey: "foo"] == nil)
    }

    // MARK: - Encoding

    @Test("encodeLogEntry returns non-nil for valid entry")
    @available(LambdaSwift 2.0, *)
    func encodeReturnsData() {
        let logEntry = JSONLogHandler.LogEntry(
            timestamp: Date(),
            level: "INFO",
            message: "test",
            requestId: "r",
            traceId: "t",
            file: "Test.swift",
            function: "test()",
            line: 1,
            metadata: nil
        )
        let data = JSONLogHandler.encodeLogEntry(logEntry)
        #expect(data != nil)
        #expect(data?.isEmpty == false)
    }

    // MARK: - writeAll (write loop)

    /// Creates a minimal handler instance for testing writeAll.
    @available(LambdaSwift 2.0, *)
    private func makeHandler() -> JSONLogHandler {
        JSONLogHandler(label: "test", requestID: "r", traceID: "t")
    }

    @Test("writeAll writes all bytes in a single call when write succeeds fully")
    @available(LambdaSwift 2.0, *)
    func writeAllSingleCall() {
        let handler = makeHandler()
        let data = Data("hello".utf8)
        var callCount = 0
        let written = handler.writeAll(data) { _, count in
            callCount += 1
            return count  // write everything at once
        }
        #expect(written == data.count)
        #expect(callCount == 1)
    }

    @Test("writeAll handles partial writes by looping until all bytes are written")
    @available(LambdaSwift 2.0, *)
    func writeAllPartialWrites() {
        let handler = makeHandler()
        let data = Data("hello world!".utf8)  // 12 bytes
        var callCount = 0
        let written = handler.writeAll(data) { _, count in
            callCount += 1
            // Simulate writing at most 4 bytes per call
            return min(count, 4)
        }
        #expect(written == data.count)
        #expect(callCount == 3)  // 4 + 4 + 4
    }

    @Test("writeAll retries on EINTR and eventually succeeds")
    @available(LambdaSwift 2.0, *)
    func writeAllRetriesOnEINTR() {
        let handler = makeHandler()
        let data = Data("abc".utf8)
        var callCount = 0
        let written = handler.writeAll(data) { _, count in
            callCount += 1
            if callCount <= 2 {
                // Simulate EINTR on first two attempts
                errno = EINTR
                return -1
            }
            return count
        }
        #expect(written == data.count)
        #expect(callCount == 3)
    }

    @Test("writeAll stops and returns partial count on non-EINTR error")
    @available(LambdaSwift 2.0, *)
    func writeAllStopsOnError() {
        let handler = makeHandler()
        let data = Data("hello world!".utf8)  // 12 bytes
        var callCount = 0
        let written = handler.writeAll(data) { _, count in
            callCount += 1
            if callCount == 1 {
                return min(count, 4)  // write 4 bytes
            }
            // Fail with ENOSPC on second call
            errno = ENOSPC
            return -1
        }
        #expect(written == 4)
        #expect(callCount == 2)
    }

    @Test("writeAll returns 0 for empty data")
    @available(LambdaSwift 2.0, *)
    func writeAllEmptyData() {
        let handler = makeHandler()
        let data = Data()
        var callCount = 0
        let written = handler.writeAll(data) { _, count in
            callCount += 1
            return count
        }
        #expect(written == 0)
        #expect(callCount == 0)
    }
}
