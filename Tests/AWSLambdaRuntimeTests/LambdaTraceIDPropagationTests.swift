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

#if os(macOS)
import Darwin.C
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

@Suite("Trace ID Propagation Tests", .serialized)
struct LambdaTraceIDPropagationTests {

    // MARK: - TaskLocal basic behavior

    @Test("currentTraceID returns nil outside invocation scope")
    @available(LambdaSwift 2.0, *)
    func currentTraceIDIsNilOutsideScope() async {
        #expect(LambdaContext.currentTraceID == nil)
    }

    @Test("currentTraceID returns value inside withValue scope")
    @available(LambdaSwift 2.0, *)
    func currentTraceIDAvailableInsideScope() async {
        let expectedTraceID = "Root=1-abc-def123;Sampled=1"

        await LambdaContext.$currentTraceID.withValue(expectedTraceID) {
            #expect(LambdaContext.currentTraceID == expectedTraceID)
        }

        // After scope ends, should be nil again
        #expect(LambdaContext.currentTraceID == nil)
    }

    @Test("currentTraceID is isolated between concurrent tasks")
    @available(LambdaSwift 2.0, *)
    func currentTraceIDIsolatedBetweenConcurrentTasks() async {
        let traceID1 = "Root=1-aaa-111;Sampled=1"
        let traceID2 = "Root=1-bbb-222;Sampled=1"
        let traceID3 = "Root=1-ccc-333;Sampled=1"

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await LambdaContext.$currentTraceID.withValue(traceID1) {
                    // Simulate some async work
                    try? await Task.sleep(for: .milliseconds(50))
                    #expect(LambdaContext.currentTraceID == traceID1)
                }
            }
            group.addTask {
                await LambdaContext.$currentTraceID.withValue(traceID2) {
                    try? await Task.sleep(for: .milliseconds(50))
                    #expect(LambdaContext.currentTraceID == traceID2)
                }
            }
            group.addTask {
                await LambdaContext.$currentTraceID.withValue(traceID3) {
                    try? await Task.sleep(for: .milliseconds(50))
                    #expect(LambdaContext.currentTraceID == traceID3)
                }
            }
            await group.waitForAll()
        }
    }

    @Test("currentTraceID propagates to child tasks")
    @available(LambdaSwift 2.0, *)
    func currentTraceIDPropagatesToChildTasks() async {
        let expectedTraceID = "Root=1-child-test;Sampled=1"

        await LambdaContext.$currentTraceID.withValue(expectedTraceID) {
            // Child task should inherit the TaskLocal value
            await withTaskGroup(of: String?.self) { group in
                group.addTask {
                    LambdaContext.currentTraceID
                }
                for await childTraceID in group {
                    #expect(childTraceID == expectedTraceID)
                }
            }
        }
    }

    // MARK: - Environment variable behavior

    @Test("_X_AMZN_TRACE_ID env var is set and cleared in single-concurrency simulation")
    @available(LambdaSwift 2.0, *)
    func envVarSetAndClearedInSingleConcurrency() async {
        let traceID = "Root=1-envvar-test;Sampled=1"

        // Ensure it's not set before
        unsetenv("_X_AMZN_TRACE_ID")
        #expect(Lambda.env("_X_AMZN_TRACE_ID") == nil)

        // Simulate what the run loop does in single-concurrency mode
        await LambdaContext.$currentTraceID.withValue(traceID) {
            setenv("_X_AMZN_TRACE_ID", traceID, 1)
            defer { unsetenv("_X_AMZN_TRACE_ID") }

            // During handler execution, env var should be set
            #expect(Lambda.env("_X_AMZN_TRACE_ID") == traceID)
            #expect(LambdaContext.currentTraceID == traceID)
        }

        // After scope ends, env var should be cleared
        #expect(Lambda.env("_X_AMZN_TRACE_ID") == nil)
    }

    @Test("_X_AMZN_TRACE_ID env var is NOT set in multi-concurrency simulation")
    @available(LambdaSwift 2.0, *)
    func envVarNotSetInMultiConcurrency() async {
        let traceID = "Root=1-multi-test;Sampled=1"

        // Ensure it's not set before
        unsetenv("_X_AMZN_TRACE_ID")

        // Simulate what the run loop does in multi-concurrency mode (isSingleConcurrencyMode = false)
        // The env var should NOT be set, only the TaskLocal
        await LambdaContext.$currentTraceID.withValue(traceID) {
            // In multi-concurrency mode, we skip setenv entirely
            // TaskLocal should still work
            #expect(LambdaContext.currentTraceID == traceID)
            // Env var should NOT be set
            #expect(Lambda.env("_X_AMZN_TRACE_ID") == nil)
        }
    }

    // MARK: - Background task propagation

    @Test("currentTraceID remains available during simulated background work")
    @available(LambdaSwift 2.0, *)
    func currentTraceIDAvailableDuringBackgroundWork() async {
        let traceID = "Root=1-background-test;Sampled=1"

        await LambdaContext.$currentTraceID.withValue(traceID) {
            // Simulate sending response (the trace ID should still be available after)
            #expect(LambdaContext.currentTraceID == traceID)

            // Simulate background work after response
            try? await Task.sleep(for: .milliseconds(10))
            #expect(LambdaContext.currentTraceID == traceID)

            // Even deeper async work
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    try? await Task.sleep(for: .milliseconds(10))
                    #expect(LambdaContext.currentTraceID == traceID)
                }
                await group.waitForAll()
            }
        }
    }

    // MARK: - Coexistence with instance property

    @Test("TaskLocal currentTraceID and instance traceID coexist independently")
    @available(LambdaSwift 2.0, *)
    func taskLocalAndInstancePropertyCoexist() async {
        let taskLocalTraceID = "Root=1-tasklocal;Sampled=1"
        let instanceTraceID = "Root=1-instance;Sampled=0"

        await LambdaContext.$currentTraceID.withValue(taskLocalTraceID) {
            let context = LambdaContext.__forTestsOnly(
                requestID: "test-request",
                traceID: instanceTraceID,
                tenantID: nil,
                invokedFunctionARN: "arn:aws:lambda:us-east-1:123456789:function:test",
                timeout: .seconds(30),
                logger: .init(label: "test")
            )

            // Instance property returns its own value
            #expect(context.traceID == instanceTraceID)
            // TaskLocal returns the TaskLocal value
            #expect(LambdaContext.currentTraceID == taskLocalTraceID)
        }
    }
}
