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

import ServiceContextModule
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

    // MARK: - ServiceContext basic behavior

    @Test("ServiceContext traceID returns nil outside invocation scope")
    @available(LambdaSwift 2.0, *)
    func traceIDIsNilOutsideScope() async {
        #expect(ServiceContext.current?.traceID == nil)
    }

    @Test("ServiceContext traceID returns value inside withValue scope")
    @available(LambdaSwift 2.0, *)
    func traceIDAvailableInsideScope() async {
        let expectedTraceID = "Root=1-abc-def123;Sampled=1"

        var context = ServiceContext.topLevel
        context.traceID = expectedTraceID

        ServiceContext.withValue(context) {
            #expect(ServiceContext.current?.traceID == expectedTraceID)
        }

        // After scope ends, should be nil again
        #expect(ServiceContext.current?.traceID == nil)
    }

    @Test("ServiceContext traceID is isolated between concurrent tasks")
    @available(LambdaSwift 2.0, *)
    func traceIDIsolatedBetweenConcurrentTasks() async {
        let traceID1 = "Root=1-aaa-111;Sampled=1"
        let traceID2 = "Root=1-bbb-222;Sampled=1"
        let traceID3 = "Root=1-ccc-333;Sampled=1"

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                var ctx = ServiceContext.topLevel
                ctx.traceID = traceID1
                await ServiceContext.withValue(ctx) {
                    try? await Task.sleep(for: .milliseconds(50))
                    #expect(ServiceContext.current?.traceID == traceID1)
                }
            }
            group.addTask {
                var ctx = ServiceContext.topLevel
                ctx.traceID = traceID2
                await ServiceContext.withValue(ctx) {
                    try? await Task.sleep(for: .milliseconds(50))
                    #expect(ServiceContext.current?.traceID == traceID2)
                }
            }
            group.addTask {
                var ctx = ServiceContext.topLevel
                ctx.traceID = traceID3
                await ServiceContext.withValue(ctx) {
                    try? await Task.sleep(for: .milliseconds(50))
                    #expect(ServiceContext.current?.traceID == traceID3)
                }
            }
            await group.waitForAll()
        }
    }

    @Test("ServiceContext traceID propagates to child tasks")
    @available(LambdaSwift 2.0, *)
    func traceIDPropagatesToChildTasks() async {
        let expectedTraceID = "Root=1-child-test;Sampled=1"

        var ctx = ServiceContext.topLevel
        ctx.traceID = expectedTraceID

        await ServiceContext.withValue(ctx) {
            await withTaskGroup(of: String?.self) { group in
                group.addTask {
                    ServiceContext.current?.traceID
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

        var ctx = ServiceContext.topLevel
        ctx.traceID = traceID

        await ServiceContext.withValue(ctx) {
            setenv("_X_AMZN_TRACE_ID", traceID, 1)
            defer { unsetenv("_X_AMZN_TRACE_ID") }

            #expect(Lambda.env("_X_AMZN_TRACE_ID") == traceID)
            #expect(ServiceContext.current?.traceID == traceID)
        }

        #expect(Lambda.env("_X_AMZN_TRACE_ID") == nil)
    }

    @Test("_X_AMZN_TRACE_ID env var is NOT set in multi-concurrency simulation")
    @available(LambdaSwift 2.0, *)
    func envVarNotSetInMultiConcurrency() async {
        let traceID = "Root=1-multi-test;Sampled=1"

        unsetenv("_X_AMZN_TRACE_ID")

        var ctx = ServiceContext.topLevel
        ctx.traceID = traceID

        await ServiceContext.withValue(ctx) {
            #expect(ServiceContext.current?.traceID == traceID)
            #expect(Lambda.env("_X_AMZN_TRACE_ID") == nil)
        }
    }

    // MARK: - Background task propagation

    @Test("ServiceContext traceID remains available during simulated background work")
    @available(LambdaSwift 2.0, *)
    func traceIDAvailableDuringBackgroundWork() async {
        let traceID = "Root=1-background-test;Sampled=1"

        var ctx = ServiceContext.topLevel
        ctx.traceID = traceID

        await ServiceContext.withValue(ctx) {
            #expect(ServiceContext.current?.traceID == traceID)

            try? await Task.sleep(for: .milliseconds(10))
            #expect(ServiceContext.current?.traceID == traceID)

            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    try? await Task.sleep(for: .milliseconds(10))
                    #expect(ServiceContext.current?.traceID == traceID)
                }
                await group.waitForAll()
            }
        }
    }

    // MARK: - Coexistence with instance property

    @Test("ServiceContext traceID and LambdaContext instance traceID coexist independently")
    @available(LambdaSwift 2.0, *)
    func serviceContextAndInstancePropertyCoexist() async {
        let serviceContextTraceID = "Root=1-tasklocal;Sampled=1"
        let instanceTraceID = "Root=1-instance;Sampled=0"

        var ctx = ServiceContext.topLevel
        ctx.traceID = serviceContextTraceID

        await ServiceContext.withValue(ctx) {
            let lambdaContext = LambdaContext.__forTestsOnly(
                requestID: "test-request",
                traceID: instanceTraceID,
                tenantID: nil,
                invokedFunctionARN: "arn:aws:lambda:us-east-1:123456789:function:test",
                timeout: .seconds(30),
                logger: .init(label: "test")
            )

            #expect(lambdaContext.traceID == instanceTraceID)
            #expect(ServiceContext.current?.traceID == serviceContextTraceID)
        }
    }

    @Test("ServiceContext traceID and LambdaContext instance traceID match when set from the same source")
    @available(LambdaSwift 2.0, *)
    func serviceContextAndInstanceTraceIDMatchFromSameSource() async {
        let traceID = "Root=1-65af3dc0-abc123def456;Sampled=1"

        var ctx = ServiceContext.topLevel
        ctx.traceID = traceID

        await ServiceContext.withValue(ctx) {
            let lambdaContext = LambdaContext.__forTestsOnly(
                requestID: "test-request",
                traceID: traceID,
                tenantID: nil,
                invokedFunctionARN: "arn:aws:lambda:us-east-1:123456789:function:test",
                timeout: .seconds(30),
                logger: .init(label: "test")
            )

            #expect(lambdaContext.traceID == ServiceContext.current?.traceID)
        }
    }
}
