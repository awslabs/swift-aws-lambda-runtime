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
import Synchronization
import Testing

@available(LambdaSwift 2.0, *)
struct CollectEverythingLogHandler: LogHandler {
    var metadata: Logger.Metadata = [:]
    var logLevel: Logger.Level = .info
    let logStore: LogStore

    final class LogStore: Sendable {
        struct Entry: Sendable {
            var level: Logger.Level
            var message: String
            var metadata: [String: String]
        }

        let logs: Mutex<[Entry]> = .init([])

        func append(level: Logger.Level, message: Logger.Message, metadata: Logger.Metadata?) {
            self.logs.withLock { entries in
                entries.append(
                    Entry(
                        level: level,
                        message: message.description,
                        metadata: metadata?.mapValues { $0.description } ?? [:]
                    )
                )
            }
        }

        func clear() {
            self.logs.withLock {
                $0.removeAll()
            }
        }

        enum LogFieldExpectedValue: ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
            case exactMatch(String)
            case beginsWith(String)
            case wildcard
            case predicate((String) -> Bool)

            init(stringLiteral value: String) {
                self = .exactMatch(value)
            }
        }

        @discardableResult
        func assertContainsLog(
            _ message: String,
            _ metadata: (String, LogFieldExpectedValue)...,
            sourceLocation: SourceLocation = #_sourceLocation
        ) -> [Entry] {
            var candidates = self.getAllLogsWithMessage(message)
            if candidates.isEmpty {
                Issue.record("Logs do not contain entry with message: \(message)", sourceLocation: sourceLocation)
                return []
            }
            for (key, value) in metadata {
                var errorMsg: String
                switch value {
                case .wildcard:
                    candidates = candidates.filter { $0.metadata.contains { $0.key == key } }
                    errorMsg = "Logs do not contain entry with message: \(message) and metadata: \(key) *"
                case .predicate(let predicate):
                    candidates = candidates.filter { $0.metadata[key].map(predicate) ?? false }
                    errorMsg =
                        "Logs do not contain entry with message: \(message) and metadata: \(key) matching predicate"
                case .beginsWith(let prefix):
                    candidates = candidates.filter { $0.metadata[key]?.hasPrefix(prefix) ?? false }
                    errorMsg = "Logs do not contain entry with message: \(message) and metadata: \(key), \(value)"
                case .exactMatch(let value):
                    candidates = candidates.filter { $0.metadata[key] == value }
                    errorMsg = "Logs do not contain entry with message: \(message) and metadata: \(key), \(value)"
                }
                if candidates.isEmpty {
                    Issue.record("Error: \(errorMsg)", sourceLocation: sourceLocation)
                    return []
                }
            }
            return candidates
        }

        func assertDoesNotContainMessage(_ message: String, sourceLocation: SourceLocation = #_sourceLocation) {
            let candidates = self.getAllLogsWithMessage(message)
            if candidates.count > 0 {
                Issue.record("Logs contain entry with message: \(message)", sourceLocation: sourceLocation)
            }
        }

        func getAllLogs() -> [Entry] {
            self.logs.withLock { $0 }
        }

        func getAllLogsWithMessage(_ message: String) -> [Entry] {
            self.getAllLogs().filter { $0.message == message }
        }
    }

    init(logStore: LogStore) {
        self.logStore = logStore
    }

    func log(event: LogEvent) {
        self.logStore.append(
            level: event.level,
            message: event.message,
            metadata: self.metadata.merging(event.metadata ?? [:]) { $1 }
        )
    }

    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get {
            self.metadata[key]
        }
        set {
            self.metadata[key] = newValue
        }
    }
}
