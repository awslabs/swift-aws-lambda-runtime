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

@available(LambdaSwift 2.0, *)
public struct JSONLogHandler: LogHandler {
    public var logLevel: Logger.Level
    public var metadata: Logger.Metadata = [:]

    private let label: String
    private let requestID: String
    private let traceID: String

    public init(label: String, logLevel: Logger.Level = .info, requestID: String, traceID: String) {
        self.label = label
        self.logLevel = logLevel
        self.requestID = requestID
        self.traceID = traceID
    }

    public func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata: Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        // Merge metadata
        var allMetadata = self.metadata
        if let metadata = metadata {
            allMetadata.merge(metadata) { _, new in new }
        }

        // Create log entry struct
        let logEntry = LogEntry(
            timestamp: Date(),
            level: Self.mapLogLevel(level),
            message: message.description,
            requestId: self.requestID,
            traceId: self.traceID,
            metadata: allMetadata.isEmpty ? nil : allMetadata.mapValues { $0.description }
        )

        // Encode to JSON and write to stderr using POSIX write() on fd 2.
        // We avoid print() because Swift's stdout is fully buffered on Lambda (no TTY),
        // causing log lines to never be flushed before the invocation completes.
        // POSIX write() on fd 2 is unbuffered and avoids referencing the global
        // `stderr` C pointer which is not concurrency-safe on Linux/Swift 6.
        // We create a new encoder per call to avoid sharing a mutable reference type
        // across concurrent log calls, since JSONEncoder is not thread-safe.
        // JSONEncoder allocation is on the order of nanoseconds — the JSON serialization
        // and the write() syscall dominate the cost by orders of magnitude.
        // If profiling ever shows this matters, consider manual JSON serialization
        // which would also bypass the Codable overhead entirely.
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = []  // Compact output (no pretty printing)
        if let jsonData = try? encoder.encode(logEntry) {
            var output = jsonData
            output.append(contentsOf: "\n".utf8)
            output.withUnsafeBytes { buffer in
                #if canImport(Darwin)
                _ = Darwin.write(2, buffer.baseAddress!, buffer.count)
                #elseif canImport(Glibc)
                _ = Glibc.write(2, buffer.baseAddress!, buffer.count)
                #elseif canImport(Musl)
                _ = Musl.write(2, buffer.baseAddress!, buffer.count)
                #endif
            }
        }
    }

    private static func mapLogLevel(_ level: Logger.Level) -> String {
        switch level {
        case .trace: return "TRACE"
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .notice: return "INFO"
        case .warning: return "WARN"
        case .error: return "ERROR"
        case .critical: return "FATAL"
        }
    }

    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    // MARK: - Log Entry Structure

    private struct LogEntry: Codable {
        let timestamp: Date
        let level: String
        let message: String
        let requestId: String
        let traceId: String
        let metadata: [String: String]?
    }
}
