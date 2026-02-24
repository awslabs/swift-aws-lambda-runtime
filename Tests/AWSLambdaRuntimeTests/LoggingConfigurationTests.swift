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

// These tests manipulate process-wide environment variables, so they must run serially.
@Suite(.serialized)
struct LoggingConfigurationTests {

    // MARK: - Helpers

    /// Sets environment variables for the duration of a closure, then restores them.
    private func withEnvironment(
        _ vars: [String: String?],
        body: () throws -> Void
    ) rethrows {
        var originals: [String: String?] = [:]
        for (key, value) in vars {
            originals[key] = getenv(key).map { String(cString: $0) }
            if let value {
                setenv(key, value, 1)
            } else {
                unsetenv(key)
            }
        }
        defer {
            for (key, original) in originals {
                if let original {
                    setenv(key, original, 1)
                } else {
                    unsetenv(key)
                }
            }
        }
        try body()
    }

    private let envKeys = ["AWS_LAMBDA_LOG_FORMAT", "AWS_LAMBDA_LOG_LEVEL", "LOG_LEVEL"]

    /// Clears all logging-related env vars, runs body, then restores.
    private func withCleanEnvironment(body: () throws -> Void) rethrows {
        try withEnvironment(Dictionary(uniqueKeysWithValues: envKeys.map { ($0, nil as String?) }), body: body)
    }

    // MARK: - Format Parsing

    @Test("Default format is text when AWS_LAMBDA_LOG_FORMAT is not set")
    @available(LambdaSwift 2.0, *)
    func defaultFormatIsText() {
        withCleanEnvironment {
            let config = LoggingConfiguration(logger: Logger(label: "test"))
            #expect(config.format == .text)
        }
    }

    @Test("Format is text when AWS_LAMBDA_LOG_FORMAT=Text")
    @available(LambdaSwift 2.0, *)
    func explicitTextFormat() {
        withCleanEnvironment {
            withEnvironment(["AWS_LAMBDA_LOG_FORMAT": "Text"]) {
                let config = LoggingConfiguration(logger: Logger(label: "test"))
                #expect(config.format == .text)
            }
        }
    }

    @Test("Format is JSON when AWS_LAMBDA_LOG_FORMAT=JSON")
    @available(LambdaSwift 2.0, *)
    func jsonFormat() {
        withCleanEnvironment {
            withEnvironment(["AWS_LAMBDA_LOG_FORMAT": "JSON"]) {
                let config = LoggingConfiguration(logger: Logger(label: "test"))
                #expect(config.format == .json)
            }
        }
    }

    @Test("Invalid format falls back to text")
    @available(LambdaSwift 2.0, *)
    func invalidFormatFallsBackToText() {
        withCleanEnvironment {
            withEnvironment(["AWS_LAMBDA_LOG_FORMAT": "INVALID"]) {
                let config = LoggingConfiguration(logger: Logger(label: "test"))
                #expect(config.format == .text)
            }
        }
    }

    // MARK: - Default Log Level

    @Test("No log level when no env vars are set")
    @available(LambdaSwift 2.0, *)
    func noLogLevelByDefault() {
        withCleanEnvironment {
            let config = LoggingConfiguration(logger: Logger(label: "test"))
            #expect(config.applicationLogLevel == nil)
        }
    }

    // MARK: - JSON Format Precedence

    @Test("JSON format: AWS_LAMBDA_LOG_LEVEL takes precedence over LOG_LEVEL")
    @available(LambdaSwift 2.0, *)
    func jsonPrefersAwsLogLevel() {
        withCleanEnvironment {
            withEnvironment([
                "AWS_LAMBDA_LOG_FORMAT": "JSON",
                "AWS_LAMBDA_LOG_LEVEL": "ERROR",
                "LOG_LEVEL": "DEBUG",
            ]) {
                let config = LoggingConfiguration(logger: Logger(label: "test"))
                #expect(config.applicationLogLevel == .error)
            }
        }
    }

    @Test("JSON format: uses AWS_LAMBDA_LOG_LEVEL when only it is set")
    @available(LambdaSwift 2.0, *)
    func jsonUsesAwsLogLevelAlone() {
        withCleanEnvironment {
            withEnvironment([
                "AWS_LAMBDA_LOG_FORMAT": "JSON",
                "AWS_LAMBDA_LOG_LEVEL": "TRACE",
            ]) {
                let config = LoggingConfiguration(logger: Logger(label: "test"))
                #expect(config.applicationLogLevel == .trace)
            }
        }
    }

    @Test("JSON format: falls back to LOG_LEVEL when AWS_LAMBDA_LOG_LEVEL is not set")
    @available(LambdaSwift 2.0, *)
    func jsonFallsBackToLogLevel() {
        withCleanEnvironment {
            withEnvironment([
                "AWS_LAMBDA_LOG_FORMAT": "JSON",
                "LOG_LEVEL": "WARN",
            ]) {
                let config = LoggingConfiguration(logger: Logger(label: "test"))
                #expect(config.applicationLogLevel == .warning)
            }
        }
    }

    // MARK: - Text Format Precedence

    @Test("Text format: LOG_LEVEL takes precedence over AWS_LAMBDA_LOG_LEVEL")
    @available(LambdaSwift 2.0, *)
    func textPrefersLogLevel() {
        withCleanEnvironment {
            withEnvironment([
                "AWS_LAMBDA_LOG_FORMAT": "Text",
                "AWS_LAMBDA_LOG_LEVEL": "ERROR",
                "LOG_LEVEL": "DEBUG",
            ]) {
                let config = LoggingConfiguration(logger: Logger(label: "test"))
                #expect(config.applicationLogLevel == .debug)
            }
        }
    }

    @Test("Text format: uses LOG_LEVEL when only it is set")
    @available(LambdaSwift 2.0, *)
    func textUsesLogLevelAlone() {
        withCleanEnvironment {
            withEnvironment(["LOG_LEVEL": "ERROR"]) {
                let config = LoggingConfiguration(logger: Logger(label: "test"))
                #expect(config.applicationLogLevel == .error)
            }
        }
    }

    @Test("Text format: falls back to AWS_LAMBDA_LOG_LEVEL when LOG_LEVEL is not set")
    @available(LambdaSwift 2.0, *)
    func textFallsBackToAwsLogLevel() {
        withCleanEnvironment {
            withEnvironment(["AWS_LAMBDA_LOG_LEVEL": "TRACE"]) {
                let config = LoggingConfiguration(logger: Logger(label: "test"))
                #expect(config.applicationLogLevel == .trace)
            }
        }
    }

    // MARK: - Log Level Parsing

    @Test("All log level strings are parsed correctly")
    @available(LambdaSwift 2.0, *)
    func logLevelParsing() {
        let cases: [(String, Logger.Level)] = [
            ("TRACE", .trace),
            ("DEBUG", .debug),
            ("INFO", .info),
            ("WARN", .warning),
            ("WARNING", .warning),
            ("ERROR", .error),
            ("FATAL", .critical),
            ("CRITICAL", .critical),
        ]
        for (input, expected) in cases {
            withCleanEnvironment {
                withEnvironment(["AWS_LAMBDA_LOG_LEVEL": input]) {
                    let config = LoggingConfiguration(logger: Logger(label: "test"))
                    #expect(config.applicationLogLevel == expected, "Expected \(input) to parse as \(expected)")
                }
            }
        }
    }

    @Test("Unknown log level string defaults to nil")
    @available(LambdaSwift 2.0, *)
    func unknownLogLevelDefaultsToNil() {
        withCleanEnvironment {
            withEnvironment(["AWS_LAMBDA_LOG_LEVEL": "UNKNOWN"]) {
                let config = LoggingConfiguration(logger: Logger(label: "test"))
                #expect(config.applicationLogLevel == nil)
            }
        }
    }

    // MARK: - Logger Creation

    @Test("makeRuntimeLogger in text mode returns logger with configured level")
    @available(LambdaSwift 2.0, *)
    func makeRuntimeLoggerTextMode() {
        withCleanEnvironment {
            withEnvironment(["LOG_LEVEL": "ERROR"]) {
                let config = LoggingConfiguration(logger: Logger(label: "test"))
                let logger = config.makeRuntimeLogger()
                #expect(logger.logLevel == .error)
            }
        }
    }

    @Test("makeRuntimeLogger in JSON mode returns logger with configured level")
    @available(LambdaSwift 2.0, *)
    func makeRuntimeLoggerJsonMode() {
        withCleanEnvironment {
            withEnvironment([
                "AWS_LAMBDA_LOG_FORMAT": "JSON",
                "AWS_LAMBDA_LOG_LEVEL": "DEBUG",
            ]) {
                let config = LoggingConfiguration(logger: Logger(label: "test"))
                let logger = config.makeRuntimeLogger()
                #expect(logger.logLevel == .debug)
            }
        }
    }

    @Test("makeLogger creates logger with request metadata in text mode")
    @available(LambdaSwift 2.0, *)
    func makeLoggerTextModeMetadata() {
        withCleanEnvironment {
            let logStore = CollectEverythingLogHandler.LogStore()
            let baseLogger = Logger(label: "test") { _ in CollectEverythingLogHandler(logStore: logStore) }

            let config = LoggingConfiguration(logger: baseLogger)
            let logger = config.makeLogger(label: "Lambda", requestID: "req-123", traceID: "trace-456")

            logger.info("test message")

            let logs = logStore.getAllLogs()
            #expect(logs.count == 1)
            #expect(logs[0].metadata["aws-request-id"] == "req-123")
            #expect(logs[0].metadata["aws-trace-id"] == "trace-456")
        }
    }

    @Test("makeLogger in JSON mode applies configured log level")
    @available(LambdaSwift 2.0, *)
    func makeLoggerJsonModeLevel() {
        withCleanEnvironment {
            withEnvironment([
                "AWS_LAMBDA_LOG_FORMAT": "JSON",
                "AWS_LAMBDA_LOG_LEVEL": "ERROR",
            ]) {
                let config = LoggingConfiguration(logger: Logger(label: "test"))
                let logger = config.makeLogger(label: "Lambda", requestID: "req-123", traceID: "trace-456")
                #expect(logger.logLevel == .error)
            }
        }
    }
}
