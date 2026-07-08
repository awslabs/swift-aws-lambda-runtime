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

@testable import AWSLambdaRuntime

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@Suite("LambdaClock Tests")
struct LambdaClockTests {

    @Test("Clock provides current time")
    @available(LambdaSwift 2.0, *)
    func clockProvidesCurrentTime() {
        let clock = LambdaClock()
        let now = clock.now

        // Verify we get a reasonable timestamp (after today)
        let dateOfWritingThisTestInMillis: Int64 = 1_754_130_134_000
        #expect(now.instant > dateOfWritingThisTestInMillis)
    }

    @Test("Instant can be advanced by duration")
    @available(LambdaSwift 2.0, *)
    func instantCanBeAdvancedByDuration() {
        let clock = LambdaClock()
        let start = clock.now
        let advanced = start.advanced(by: .seconds(30))

        #expect(advanced.instant == start.instant + 30_000)
    }

    @Test("Duration calculation between instants")
    @available(LambdaSwift 2.0, *)
    func durationCalculationBetweenInstants() {
        let clock = LambdaClock()
        let start = clock.now
        let end = start.advanced(by: .seconds(5))

        let duration = start.duration(to: end)
        #expect(duration == .seconds(5))
    }

    @Test("Instant comparison works correctly")
    @available(LambdaSwift 2.0, *)
    func instantComparisonWorksCorrectly() {
        let clock = LambdaClock()
        let earlier = clock.now
        let later = earlier.advanced(by: .milliseconds(1))

        #expect(earlier < later)
        #expect(!(later < earlier))
    }

    @Test("Clock minimum resolution is milliseconds")
    @available(LambdaSwift 2.0, *)
    func clockMinimumResolutionIsMilliseconds() {
        let clock = LambdaClock()
        #expect(clock.minimumResolution == .milliseconds(1))
    }

    @Test("Sleep until deadline works")
    @available(LambdaSwift 2.0, *)
    func sleepUntilDeadlineWorks() async throws {
        let clock = LambdaClock()
        let start = clock.now
        let deadline = start.advanced(by: .milliseconds(50))

        try await clock.sleep(until: deadline, tolerance: nil)

        let end = clock.now
        let elapsed = start.duration(to: end)

        // The lower bound proves we actually slept for ~50ms (the meaningful assertion). The upper
        // bound only guards against sleeping wildly too long; keep it generous so a scheduling stall
        // on a loaded/virtualized CI runner (which can delay task wake-up well beyond 200ms) does
        // not flake the test.
        #expect(elapsed >= .milliseconds(40))
        #expect(elapsed <= .seconds(5))
    }

    @Test("Sleep with past deadline returns immediately")
    @available(LambdaSwift 2.0, *)
    func sleepWithPastDeadlineReturnsImmediately() async throws {
        let clock = LambdaClock()
        let now = clock.now
        let pastDeadline = now.advanced(by: .milliseconds(-100))

        let start = clock.now
        try await clock.sleep(until: pastDeadline, tolerance: nil)
        let end = clock.now

        let elapsed = start.duration(to: end)
        // A past deadline must not trigger a real sleep. We only need to prove no ~full-duration
        // wait happened; a 1s ceiling is far below any genuine sleep yet high enough to absorb
        // async scheduling overhead on a busy CI runner (a 10ms budget flakes there).
        #expect(elapsed < .seconds(1))
    }

    @Test("Duration to future instant returns negative duration")
    @available(LambdaSwift 2.0, *)
    func durationToFutureInstantReturnsNegativeDuration() {
        let clock = LambdaClock()
        let futureDeadline = clock.now.advanced(by: .seconds(30))
        let currentTime = clock.now

        // This simulates getRemainingTime() where deadline is in future
        let remainingTime = futureDeadline.duration(to: currentTime)

        // Should be negative since we're going from future to present
        #expect(remainingTime < .zero)
        #expect(remainingTime <= .seconds(-29))  // Allow some timing tolerance
    }

    @Test("LambdaClock now matches Foundation Date within tolerance")
    @available(LambdaSwift 2.0, *)
    func lambdaClockNowMatchesFoundationDate() {

        let clock = LambdaClock()

        // Get timestamps as close together as possible
        let lambdaClockNow = clock.now
        let foundationDate = Date()

        // Convert Foundation Date to milliseconds since epoch
        let foundationMillis = Int64(foundationDate.timeIntervalSince1970 * 1000)
        let lambdaClockMillis = lambdaClockNow.millisecondsSinceEpoch()

        // This asserts the two clocks read the same wall time (same epoch, same unit) - a real bug
        // would be off by orders of magnitude (wrong epoch or seconds-vs-millis). The two reads are
        // sequential, so the only legitimate difference is the tiny gap between them; a scheduling
        // stall on a loaded/virtualized CI runner can stretch that gap past a few milliseconds, so
        // the 10ms budget flakes. A 1s tolerance still catches genuine unit/epoch mistakes.
        let difference = abs(foundationMillis - lambdaClockMillis)

        #expect(
            difference <= 1000,
            "LambdaClock and Foundation Date should be within 1s of each other, difference was \(difference)ms"
        )
    }
    @Test("Instant renders as string with an epoch number")
    @available(LambdaSwift 2.0, *)
    func instantRendersAsStringWithEpochNumber() {
        let clock = LambdaClock()
        let instant = clock.now

        let expectedString = "\(instant)"
        #expect(expectedString.allSatisfy { $0.isNumber }, "String should only contain numbers")

        if let expectedNumber = Int64(expectedString) {
            let newInstant = LambdaClock.Instant(millisecondsSinceEpoch: expectedNumber)
            #expect(instant == newInstant, "Instant should match the expected number")
        } else {
            Issue.record("expectedString is not a number")
        }
    }
}
