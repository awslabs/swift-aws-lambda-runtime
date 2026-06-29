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

import Testing

@testable import AWSLambdaPluginHelper

@Suite("withRetry")
struct RetryTests {

    private struct Transient: Error {}
    private struct Fatal: Error {}

    @available(LambdaSwift 2.0, *)
    @Test("Returns immediately when the operation succeeds on the first attempt")
    func succeedsFirstAttempt() async throws {
        let attempts = Counter()
        let result = try await withRetry(
            maxAttempts: 3,
            initialDelay: .zero,
            isRetryable: { _ in true },
            operation: {
                attempts.increment()
                return 42
            }
        )
        #expect(result == 42)
        #expect(attempts.value == 1)
    }

    @available(LambdaSwift 2.0, *)
    @Test("Retries a transient failure and then succeeds")
    func retriesThenSucceeds() async throws {
        let attempts = Counter()
        let result = try await withRetry(
            maxAttempts: 5,
            initialDelay: .zero,
            isRetryable: { $0 is Transient },
            operation: {
                attempts.increment()
                if attempts.value < 3 { throw Transient() }
                return "ok"
            }
        )
        #expect(result == "ok")
        #expect(attempts.value == 3)
    }

    @available(LambdaSwift 2.0, *)
    @Test("Stops after maxAttempts and rethrows the last error")
    func exhaustsAttempts() async throws {
        let attempts = Counter()
        await #expect(throws: Transient.self) {
            try await withRetry(
                maxAttempts: 3,
                initialDelay: .zero,
                isRetryable: { $0 is Transient },
                operation: {
                    attempts.increment()
                    throw Transient()
                }
            )
        }
        #expect(attempts.value == 3)
    }

    @available(LambdaSwift 2.0, *)
    @Test("Does not retry an error the predicate rejects")
    func rethrowsNonRetryableImmediately() async throws {
        let attempts = Counter()
        await #expect(throws: Fatal.self) {
            try await withRetry(
                maxAttempts: 5,
                initialDelay: .zero,
                isRetryable: { $0 is Transient },
                operation: {
                    attempts.increment()
                    throw Fatal()
                }
            )
        }
        #expect(attempts.value == 1)
    }

    @available(LambdaSwift 2.0, *)
    @Test("Reports each retry through onRetry")
    func reportsRetries() async throws {
        let attempts = Counter()
        let retries = Counter()
        _ = try await withRetry(
            maxAttempts: 4,
            initialDelay: .zero,
            isRetryable: { $0 is Transient },
            onRetry: { _, _ in retries.increment() },
            operation: {
                attempts.increment()
                if attempts.value < 3 { throw Transient() }
                return 0
            }
        )
        // Two failures before the third, successful attempt → two retry callbacks.
        #expect(retries.value == 2)
    }

    // MARK: - backoffDelay

    @available(LambdaSwift 2.0, *)
    @Test("Base delay doubles each attempt before jitter")
    func backoffGrowsExponentially() {
        let initial = Duration.milliseconds(500)
        let maxDelay = Duration.seconds(60)
        // jitter == 1 selects the top of the window, i.e. the full (uncapped) base delay.
        #expect(backoffDelay(attempt: 1, initialDelay: initial, maxDelay: maxDelay, jitter: 1) == .milliseconds(500))
        #expect(backoffDelay(attempt: 2, initialDelay: initial, maxDelay: maxDelay, jitter: 1) == .seconds(1))
        #expect(backoffDelay(attempt: 3, initialDelay: initial, maxDelay: maxDelay, jitter: 1) == .seconds(2))
        #expect(backoffDelay(attempt: 4, initialDelay: initial, maxDelay: maxDelay, jitter: 1) == .seconds(4))
    }

    @available(LambdaSwift 2.0, *)
    @Test("Base delay is capped at maxDelay")
    func backoffIsCapped() {
        let delay = backoffDelay(
            attempt: 20,
            initialDelay: .milliseconds(500),
            maxDelay: .seconds(10),
            jitter: 1
        )
        #expect(delay == .seconds(10))
    }

    @available(LambdaSwift 2.0, *)
    @Test("Equal jitter keeps the wait within the upper half of the window")
    func jitterStaysWithinBounds() {
        let initial = Duration.seconds(4)
        // attempt 1, jitter 0 → base/2; jitter 1 → base. Window is [2s, 4s].
        #expect(backoffDelay(attempt: 1, initialDelay: initial, maxDelay: .seconds(60), jitter: 0) == .seconds(2))
        #expect(backoffDelay(attempt: 1, initialDelay: initial, maxDelay: .seconds(60), jitter: 0.5) == .seconds(3))
        #expect(backoffDelay(attempt: 1, initialDelay: initial, maxDelay: .seconds(60), jitter: 1) == .seconds(4))
    }

    @available(LambdaSwift 2.0, *)
    @Test("Out-of-range jitter is clamped to 0...1")
    func jitterIsClamped() {
        let initial = Duration.seconds(4)
        #expect(backoffDelay(attempt: 1, initialDelay: initial, maxDelay: .seconds(60), jitter: -5) == .seconds(2))
        #expect(backoffDelay(attempt: 1, initialDelay: initial, maxDelay: .seconds(60), jitter: 5) == .seconds(4))
    }
}

/// Minimal mutable counter for asserting attempt counts within `withRetry`'s non-escaping,
/// non-concurrent operation closure.
private final class Counter {
    private(set) var value = 0
    func increment() { self.value += 1 }
}
