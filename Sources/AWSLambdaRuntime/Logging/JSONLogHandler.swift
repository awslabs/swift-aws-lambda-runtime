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
    private let encoder: JSONEncoder

    public init(label: String, logLevel: Logger.Level = .info, requestID: String, traceID: String) {
        self.label = label
        self.logLevel = logLevel
        self.requestID = requestID
        self.traceID = traceID

        // Configure encoder for consistent output
        self.encoder = JSONEncoder()
        // Use ISO8601 format with fractional seconds
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = []  // Compact output (no pretty printing)
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

        // Encode and emit JSON to stdout
        if let jsonData = try? encoder.encode(logEntry),
            let jsonString = String(data: jsonData, encoding: .utf8)
        {
            print(jsonString)
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
