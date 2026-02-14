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
        let metadata: [String: String]?
    }

    /// Creates a LogEntry and encodes it, returning the decoded TestLogEntry for assertions.
    @available(LambdaSwift 2.0, *)
    private func makeAndEncode(
        level: Logger.Level = .info,
        message: String = "test",
        requestID: String = "req-1",
        traceID: String = "trace-1",
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

    // MARK: - Timestamp

    @Test("Timestamp is in ISO 8601 format")
    @available(LambdaSwift 2.0, *)
    func iso8601Timestamp() {
        let (entry, _) = makeAndEncode()
        let timestamp = entry?.timestamp
        #expect(timestamp != nil)

        // Verify it matches ISO 8601 format (e.g. "2024-01-16T10:30:45Z")
        let iso8601Pattern = #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\\d+)?Z$"#
        let matches = timestamp?.range(of: iso8601Pattern, options: .regularExpression) != nil
        #expect(matches, "Timestamp '\(timestamp ?? "")' should be in ISO 8601 format")
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
            metadata: nil
        )
        let data = JSONLogHandler.encodeLogEntry(logEntry)
        #expect(data != nil)
        #expect(data?.isEmpty == false)
    }
}
