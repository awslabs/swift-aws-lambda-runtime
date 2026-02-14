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

@available(LambdaSwift 2.0, *)
public struct LoggingConfiguration: Sendable {
    public enum LogFormat: String, Sendable {
        case text = "Text"
        case json = "JSON"
    }

    public let format: LogFormat
    public let applicationLogLevel: Logger.Level?
    private let baseLogger: Logger

    /// Note: No log messages are emitted during initialization because the logging
    /// configuration is not yet fully constructed. The provided `logger` still uses its
    /// original format and log level, so any messages emitted here would bypass the
    /// configured format (e.g. appearing as plain text when JSON mode is selected).
    /// Callers should use `makeRuntimeLogger()` after initialization to obtain a
    /// properly configured logger for any diagnostic messages.
    public init(logger: Logger) {
        // Read AWS_LAMBDA_LOG_FORMAT (default: Text)
        self.format =
            LogFormat(
                rawValue: Lambda.env("AWS_LAMBDA_LOG_FORMAT") ?? "Text"
            ) ?? .text

        // Store the base logger for cloning
        self.baseLogger = logger

        // Determine log level with proper precedence
        // When both AWS_LAMBDA_LOG_LEVEL and LOG_LEVEL are set:
        //   - JSON format: AWS_LAMBDA_LOG_LEVEL takes precedence
        //   - Text format: LOG_LEVEL takes precedence (backward compatibility)
        let awsLambdaLogLevel = Lambda.env("AWS_LAMBDA_LOG_LEVEL")
        let logLevel = Lambda.env("LOG_LEVEL")

        switch (self.format, awsLambdaLogLevel, logLevel) {
        case (.json, .some(let awsLevel), _):
            // JSON format: prefer AWS_LAMBDA_LOG_LEVEL
            self.applicationLogLevel = Self.parseLogLevel(awsLevel)

        case (.json, .none, .some(let legacyLevel)):
            // JSON format with LOG_LEVEL only - use it as fallback
            self.applicationLogLevel = Self.parseLogLevel(legacyLevel)

        case (.text, _, .some(let legacyLevel)):
            // Text format: prefer LOG_LEVEL for backward compatibility
            self.applicationLogLevel = Self.parseLogLevel(legacyLevel)

        case (.text, .some(let awsLevel), .none):
            // Text format with AWS_LAMBDA_LOG_LEVEL only
            self.applicationLogLevel = Self.parseLogLevel(awsLevel)

        case (_, .none, .none):
            // No log level configured - use default
            self.applicationLogLevel = nil
        }
    }

    private static func parseLogLevel(_ level: String) -> Logger.Level {
        switch level.uppercased() {
        case "TRACE": return .trace
        case "DEBUG": return .debug
        case "INFO": return .info
        case "WARN", "WARNING": return .warning
        case "ERROR": return .error
        case "FATAL", "CRITICAL": return .critical
        default: return .info
        }
    }

    /// Create a logger for a specific invocation
    public func makeLogger(
        label: String,
        requestID: String,
        traceID: String
    ) -> Logger {
        switch self.format {
        case .text:
            // Clone the base logger and add request metadata
            var logger = self.baseLogger
            logger[metadataKey: "aws-request-id"] = .string(requestID)
            logger[metadataKey: "aws-trace-id"] = .string(traceID)
            if let level = self.applicationLogLevel {
                logger.logLevel = level
            }
            return logger

        case .json:
            // Use JSON log handler
            var logger = Logger(label: label) { label in
                JSONLogHandler(
                    label: label,
                    requestID: requestID,
                    traceID: traceID
                )
            }
            if let level = self.applicationLogLevel {
                logger.logLevel = level
            }
            return logger
        }
    }

    /// Create a logger for runtime-level messages (before any invocation).
    /// In text mode, this returns the base logger provided by the user.
    /// In JSON mode, this creates a JSON logger using the base logger's label.
    public func makeRuntimeLogger() -> Logger {
        switch self.format {
        case .text:
            var logger = self.baseLogger
            if let level = self.applicationLogLevel {
                logger.logLevel = level
            }
            return logger

        case .json:
            var logger = Logger(label: self.baseLogger.label) { label in
                JSONLogHandler(
                    label: label,
                    requestID: "N/A",
                    traceID: "N/A"
                )
            }
            if let level = self.applicationLogLevel {
                logger.logLevel = level
            }
            return logger
        }
    }
}
