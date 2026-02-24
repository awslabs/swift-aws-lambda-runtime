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
import Darwin
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
            file: file,
            function: function,
            line: line,
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
        if let jsonData = Self.encodeLogEntry(logEntry) {
            var output = jsonData
            output.append(contentsOf: "\n".utf8)
            let bytesWritten = self.writeToStderr(output)
            if bytesWritten != output.count {
                let warning = Data(
                    "STDERR_WRITE_INCOMPLETE expected=\(output.count) written=\(bytesWritten) level=\(logEntry.level) message=\(logEntry.message)\n"
                        .utf8
                )
                self.writeToStderr(warning)
            }
        } else {
            // JSON encoding failed — emit a plain-text fallback to stderr so the log
            // message is not silently lost. This should only happen if metadata contains
            // values that cannot be encoded, which is unlikely with String-typed metadata.
            let fallback = Data(
                "JSON_ENCODE_ERROR level=\(logEntry.level) message=\(logEntry.message)\n".utf8
            )
            self.writeToStderr(fallback)
        }
    }

    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    /// Writes raw bytes to stderr (fd 2) using POSIX write().
    /// Uses a loop to handle partial writes and EINTR retries, ensuring
    /// large log lines are not silently truncated.
    /// - Returns: The number of bytes successfully written.
    @discardableResult
    private func writeToStderr(_ data: Data) -> Int {
        self.writeAll(data) { pointer, count in
            #if canImport(Darwin)
            Darwin.write(2, pointer, count)
            #elseif canImport(Glibc)
            Glibc.write(2, pointer, count)
            #elseif canImport(Musl)
            Musl.write(2, pointer, count)
            #endif
        }
    }

    /// Write loop that handles partial writes and EINTR retries.
    /// Accepts an injectable write function so tests can simulate partial writes.
    /// - Parameters:
    ///   - data: The bytes to write.
    ///   - writeFn: A function matching the POSIX `write()` signature — takes a pointer
    ///     and byte count, returns the number of bytes written or -1 on error.
    /// - Returns: The total number of bytes successfully written.
    internal func writeAll(
        _ data: Data,
        using writeFn: (_ pointer: UnsafeRawPointer, _ count: Int) -> Int
    ) -> Int {
        data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return 0 }
            var remaining = buffer.count
            var offset = 0
            while remaining > 0 {
                let written = writeFn(baseAddress + offset, remaining)
                if written < 0 {
                    // Retry on EINTR; give up on any other error
                    if errno == EINTR { continue }
                    return offset
                }
                offset += written
                remaining -= written
            }
            return offset
        }
    }

    // MARK: - Log Entry Structure

    struct LogEntry: Codable {
        let timestamp: Date
        let level: String
        let message: String
        let requestId: String
        let traceId: String
        let file: String
        let function: String
        let line: UInt
        let metadata: [String: String]?
    }

    /// Encodes a log entry to JSON data. Extracted for testability.
    /// Returns nil if encoding fails.
    internal static func encodeLogEntry(_ logEntry: LogEntry) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
        }
        encoder.outputFormatting = []  // Compact output (no pretty printing)
        return try? encoder.encode(logEntry)
    }

    /// Maps a swift-log level to the AWS Lambda log level string.
    internal static func mapLogLevel(_ level: Logger.Level) -> String {
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
}
