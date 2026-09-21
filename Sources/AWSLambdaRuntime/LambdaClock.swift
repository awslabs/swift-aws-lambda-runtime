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

#if os(macOS)
import Darwin.C
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif os(Windows)
import ucrt
#else
#error("Unsupported platform")
#endif

/// A clock implementation based on Unix epoch time for AWS Lambda runtime operations.
///
/// `LambdaClock` provides millisecond-precision timing based on the Unix epoch
/// (January 1, 1970, 00:00:00 UTC). This clock is designed for Lambda runtime
/// operations where precise wall-clock time is required.
///
/// ## Usage
///
/// ```swift
/// let clock = LambdaClock()
/// let now = clock.now
/// let deadline = now.advanced(by: .seconds(30))
///
/// // Sleep until deadline
/// try await clock.sleep(until: deadline)
/// ```
///
/// ## Performance
///
/// This clock uses `clock_gettime(CLOCK_REALTIME)` on Unix systems for
/// high-precision wall-clock time measurement with millisecond resolution.
///
/// ## TimeZone Handling
///
/// The Lambda execution environment uses UTC as a timezone,
/// `LambdaClock` operates in UTC and does not account for time zones.
/// see: TZ in https://docs.aws.amazon.com/lambda/latest/dg/configuration-envvars.html
@available(LambdaSwift 2.0, *)
public struct LambdaClock: Clock {
    public typealias Duration = Swift.Duration
    public init() {}

    /// A moment in time represented as milliseconds since the Unix epoch.
    ///
    /// `Instant` represents a specific point in time as the number of milliseconds
    /// that have elapsed since January 1, 1970, 00:00:00 UTC (Unix epoch).
    ///
    /// ## Thread Safety
    ///
    /// `Instant` is a value type and is inherently thread-safe.
    public struct Instant: InstantProtocol, CustomStringConvertible {
        /// The number of milliseconds since the Unix epoch.
        let instant: Int64

        public typealias Duration = Swift.Duration

        /// Creates a new instant by adding a duration to this instant.
        ///
        /// - Parameter duration: The duration to add to this instant.
        /// - Returns: A new instant advanced by the specified duration.
        ///
        /// ## Example
        ///
        /// ```swift
        /// let now = LambdaClock().now
        /// let future = now.advanced(by: .seconds(30))
        /// ```
        public func advanced(by duration: Duration) -> Instant {
            .init(millisecondsSinceEpoch: Int64(instant + Int64(duration / .milliseconds(1))))
        }

        /// Calculates the duration between this instant and another instant.
        ///
        /// - Parameter other: The target instant to calculate duration to.
        /// - Returns: The duration from this instant to the other instant.
        ///           Positive if `other` is in the future, negative if in the past.
        ///
        /// ## Example
        ///
        /// ```swift
        /// let start = LambdaClock().now
        /// // ... some work ...
        /// let end = LambdaClock().now
        /// let elapsed = start.duration(to: end)
        /// ```
        public func duration(to other: Instant) -> Duration {
            .milliseconds(other.instant - self.instant)
        }

        /// Compares two instants for ordering.
        ///
        /// - Parameters:
        ///   - lhs: The left-hand side instant.
        ///   - rhs: The right-hand side instant.
        /// - Returns: `true` if `lhs` represents an earlier time than `rhs`.
        public static func < (lhs: Instant, rhs: Instant) -> Bool {
            lhs.instant < rhs.instant
        }

        /// Returns this instant as the number of milliseconds since the Unix epoch.
        /// - Returns: The number of milliseconds since the Unix epoch.
        public func millisecondsSinceEpoch() -> Int64 {
            self.instant
        }

        /// Creates an instant from milliseconds since the Unix epoch.
        /// - Parameter milliseconds: The number of milliseconds since the Unix epoch.
        public init(millisecondsSinceEpoch milliseconds: Int64) {
            self.instant = milliseconds
        }

        /// Renders an Instant as an EPOCH value
        public var description: String {
            "\(self.instant)"
        }
    }

    /// The current instant according to this clock.
    ///
    /// This property returns the current wall-clock time as milliseconds
    /// since the Unix epoch.
    /// This method uses `clock_gettime(CLOCK_REALTIME)` to obtain high-precision
    /// wall-clock time.
    ///
    /// - Returns: An `Instant` representing the current time.
    public var now: Instant {
        var ts = timespec()
        clock_gettime(CLOCK_REALTIME, &ts)
        return .init(millisecondsSinceEpoch: Int64(ts.tv_sec) * 1000 + Int64(ts.tv_nsec) / 1_000_000)
    }

    /// The minimum resolution of this clock.
    ///
    /// `LambdaClock` provides millisecond resolution.
    public var minimumResolution: Duration {
        .milliseconds(1)
    }

    /// Suspends the current task until the specified deadline.
    ///
    /// - Parameters:
    ///   - deadline: The instant until which to sleep.
    ///   - tolerance: The allowed tolerance for the sleep duration. Currently unused.
    ///
    /// - Throws: `CancellationError` if the task is cancelled during sleep.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let clock = LambdaClock()
    /// let deadline = clock.now.advanced(by: .seconds(5))
    /// try await clock.sleep(until: deadline)
    /// ```
    public func sleep(until deadline: Instant, tolerance: Instant.Duration?) async throws {
        let now = self.now
        let sleepDuration = now.duration(to: deadline)
        if sleepDuration > .zero {
            try await ContinuousClock().sleep(for: sleepDuration)
        }
    }

    /// Hardcoded maximum execution time for a Lambda function.
    public static var maxLambdaExecutionTime: Duration {
        // 15 minutes in milliseconds
        // see https://docs.aws.amazon.com/lambda/latest/dg/configuration-timeout.html
        .milliseconds(15 * 60 * 1000)
    }

    /// Returns the maximum deadline for a Lambda function execution.
    /// This is the current time plus the maximum execution time.
    /// This function is only used by the local server for testing purposes.
    public static var maxLambdaDeadline: Instant {
        LambdaClock().now.advanced(by: maxLambdaExecutionTime)
    }
}
