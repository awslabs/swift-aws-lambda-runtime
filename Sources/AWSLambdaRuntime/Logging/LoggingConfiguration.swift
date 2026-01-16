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
    
    public init(logger: Logger) {
        // Read AWS_LAMBDA_LOG_FORMAT (default: Text)
        self.format = LogFormat(
            rawValue: Lambda.env("AWS_LAMBDA_LOG_FORMAT") ?? "Text"
        ) ?? .text
        
        // Determine log level with proper precedence
        let awsLambdaLogLevel = Lambda.env("AWS_LAMBDA_LOG_LEVEL")
        let logLevel = Lambda.env("LOG_LEVEL")
        
        switch (self.format, awsLambdaLogLevel, logLevel) {
        case (.json, .some(let awsLevel), .some(let legacyLevel)):
            // JSON format with both env vars set - use AWS_LAMBDA_LOG_LEVEL and warn
            self.applicationLogLevel = Self.parseLogLevel(awsLevel)
            logger.warning(
                "Both AWS_LAMBDA_LOG_LEVEL and LOG_LEVEL are set. Using AWS_LAMBDA_LOG_LEVEL for JSON format.",
                metadata: [
                    "AWS_LAMBDA_LOG_LEVEL": .string(awsLevel),
                    "LOG_LEVEL": .string(legacyLevel)
                ]
            )
            
        case (.json, .some(let awsLevel), .none):
            // JSON format with AWS_LAMBDA_LOG_LEVEL only
            self.applicationLogLevel = Self.parseLogLevel(awsLevel)
            
        case (.json, .none, .some(let legacyLevel)):
            // JSON format with LOG_LEVEL only - use it but warn
            self.applicationLogLevel = Self.parseLogLevel(legacyLevel)
            logger.warning(
                "Using LOG_LEVEL with JSON format. Consider using AWS_LAMBDA_LOG_LEVEL instead.",
                metadata: ["LOG_LEVEL": .string(legacyLevel)]
            )
            
        case (.text, .some(let awsLevel), .some(let legacyLevel)):
            // Text format with both - prefer LOG_LEVEL for backward compatibility
            self.applicationLogLevel = Self.parseLogLevel(legacyLevel)
            logger.debug(
                "Both AWS_LAMBDA_LOG_LEVEL and LOG_LEVEL are set. Using LOG_LEVEL for Text format.",
                metadata: [
                    "AWS_LAMBDA_LOG_LEVEL": .string(awsLevel),
                    "LOG_LEVEL": .string(legacyLevel)
                ]
            )
            
        case (.text, .some(let awsLevel), .none):
            // Text format with AWS_LAMBDA_LOG_LEVEL only
            self.applicationLogLevel = Self.parseLogLevel(awsLevel)
            
        case (.text, .none, .some(let legacyLevel)):
            // Text format with LOG_LEVEL only - existing behavior
            self.applicationLogLevel = Self.parseLogLevel(legacyLevel)
            
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
            // Use existing default logger
            var logger = Logger(label: label)
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
}
