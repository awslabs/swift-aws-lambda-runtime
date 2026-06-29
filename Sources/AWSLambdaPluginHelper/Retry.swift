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

/// Runs `operation`, retrying it while `isRetryable` accepts the thrown error.
///
/// AWS control-plane APIs are eventually consistent: a resource created by one call (an IAM role,
/// an S3 bucket) may not yet be usable by the next call, surfacing as a transient error. This helper
/// centralises the "try, wait, try again" pattern so each call site only has to describe *which*
/// errors are transient rather than re-implement the loop, backoff, and jitter.
///
/// Between attempts it waits with **exponential backoff and equal jitter**: the base delay doubles
/// each attempt (`initialDelay`, `2×`, `4×`, …) up to `maxDelay`, then a random component spreads the
/// actual wait across the upper half of that window. Backoff bounds the load a slow dependency sees;
/// jitter stops many concurrent deployments from retrying in lockstep (the "thundering herd").
///
/// The defaults are tuned for AWS eventual consistency, so the common call site is just
/// `withRetry(isRetryable:) { ... }`.
///
/// - Parameters:
///   - maxAttempts: The maximum number of times `operation` is invoked (must be >= 1).
///   - initialDelay: The base delay before the first retry; doubles each subsequent attempt.
///   - maxDelay: The ceiling the base delay is capped at before jitter is applied.
///   - isRetryable: Decides whether a thrown error is transient and worth retrying.
///   - onRetry: Invoked before each wait, with the attempt number just completed (1-based) and the
///     error that triggered the retry. Defaults to a no-op; used for verbose progress output.
///   - operation: The work to perform.
/// - Returns: The value produced by the first successful `operation` invocation.
/// - Throws: Rethrows the last error if every attempt fails or the error is not retryable.
@available(LambdaSwift 2.0, *)
func withRetry<Success>(
    maxAttempts: Int = 8,
    initialDelay: Duration = .milliseconds(500),
    maxDelay: Duration = .seconds(20),
    isRetryable: (any Error) -> Bool,
    onRetry: (_ attempt: Int, _ error: any Error) -> Void = { _, _ in },
    operation: () async throws -> Success
) async throws -> Success {
    precondition(maxAttempts >= 1, "maxAttempts must be at least 1")

    var attempt = 0
    while true {
        attempt += 1
        do {
            return try await operation()
        } catch {
            guard attempt < maxAttempts, isRetryable(error) else {
                throw error
            }
            onRetry(attempt, error)
            let delay = backoffDelay(
                attempt: attempt,
                initialDelay: initialDelay,
                maxDelay: maxDelay,
                jitter: Double.random(in: 0...1)
            )
            try await Task.sleep(for: delay)
        }
    }
}

/// Computes the wait before a given retry using exponential backoff with equal jitter.
///
/// The base delay is `initialDelay × 2^(attempt - 1)`, capped at `maxDelay`. Equal jitter then keeps
/// the lower half of that window fixed and randomises the upper half:
/// `base/2 + jitter × base/2`. With `jitter` in `0...1` the result lies in `[base/2, base]`, which
/// preserves a meaningful minimum wait while still de-synchronising concurrent callers.
///
/// Factored out of ``withRetry(maxAttempts:initialDelay:maxDelay:isRetryable:onRetry:operation:)`` so
/// the backoff curve and jitter can be unit tested deterministically by supplying a fixed `jitter`.
///
/// - Parameters:
///   - attempt: The 1-based number of the attempt that just failed.
///   - initialDelay: The base delay for the first retry.
///   - maxDelay: The ceiling applied to the exponential base before jitter.
///   - jitter: A value in `0...1` selecting where in the upper half of the window the wait falls.
@available(LambdaSwift 2.0, *)
func backoffDelay(attempt: Int, initialDelay: Duration, maxDelay: Duration, jitter: Double) -> Duration {
    // Clamp the exponent so the shift cannot overflow on a large maxAttempts.
    let exponent = min(max(attempt, 1) - 1, 30)
    let exponential = initialDelay * Double(1 << exponent)
    let capped = min(exponential, maxDelay)
    let clampedJitter = min(max(jitter, 0), 1)
    return capped / 2 + (capped / 2) * clampedJitter
}
