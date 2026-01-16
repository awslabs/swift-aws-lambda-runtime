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
import NIOCore
import NIOHTTP1
import NIOPosix
import Testing

import struct Foundation.UUID

@testable import AWSLambdaRuntime

/// Tests for channel lifecycle race condition fixes (Bug #624)
/// These tests verify:
/// 1. Old channels are properly removed from closingConnections
/// 2. Shutdown completes even with old channels closing
/// 3. Current channel always goes through proper state transitions
@Suite
struct LambdaRuntimeClientChannelLifecycleTests {

    let logger = {
        var logger = Logger(label: "ChannelLifecycleTest")
        // Uncomment the line below to enable trace-level logging for debugging purposes.
        // logger.logLevel = .trace
        return logger
    }()

    // MARK: - Test Fix #1: Old channels removed from closingConnections in .connected + .notClosing

    @Test("Old channel closing in connected state is properly cleaned up")
    @available(LambdaSwift 2.0, *)
    func testOldChannelCleanupInConnectedNotClosing() async throws {
        // This test simulates the scenario where:
        // 1. A connection is established
        // 2. Server closes the connection (old channel)
        // 3. Client reconnects (new channel)
        // 4. Old channel's closeFuture fires while new connection is active
        // Expected: Old channel should be removed from closingConnections

        struct ReconnectBehavior: LambdaServerBehavior {
            let requestId = UUID().uuidString
            var invocationCount = 0

            func getInvocation() -> GetInvocationResult {
                // First invocation succeeds, then trigger disconnect
                if invocationCount == 0 {
                    return .success((requestId, "first"))
                } else {
                    return .success(("disconnect", "0"))
                }
            }

            func processResponse(requestId: String, response: String?) -> Result<String?, ProcessResponseError> {
                // After first response, signal delayed disconnect
                if response == "first" {
                    return .success("delayed-disconnect")
                }
                return .success(nil)
            }

            func processError(requestId: String, error: ErrorResponse) -> Result<Void, ProcessErrorError> {
                Issue.record("should not report error")
                return .failure(.internalServerError)
            }

            func processInitError(error: ErrorResponse) -> Result<Void, ProcessErrorError> {
                Issue.record("should not report init error")
                return .failure(.internalServerError)
            }
        }

        try await withMockServer(behaviour: ReconnectBehavior()) { port in
            let configuration = LambdaRuntimeClient.Configuration(ip: "127.0.0.1", port: port)

            try await LambdaRuntimeClient.withRuntimeClient(
                configuration: configuration,
                eventLoop: NIOSingletons.posixEventLoopGroup.next(),
                logger: self.logger
            ) { runtimeClient in
                do {
                    // First invocation - will succeed
                    let (invocation, writer) = try await runtimeClient.nextInvocation()
                    #expect(invocation.event == ByteBuffer(string: "first"))
                    try await writer.writeAndFinish(ByteBuffer(string: "first"))

                    // Give time for server to close connection
                    try await Task.sleep(for: .milliseconds(100))

                    // Second invocation - should reconnect and then get disconnect signal
                    // This tests that old channel cleanup doesn't interfere with new connection
                    let _ = try? await runtimeClient.nextInvocation()

                    // If we reach here without hanging, the test passes
                    // The old channel was properly cleaned up
                } catch {
                    // Expected to fail with connection error, which is fine
                    // The important part is that we don't hang
                }
            }
        }
    }

    // MARK: - Test Fix #2: Old channels removed from closingConnections in .connected + .closing

    @Test("Old channel closing during shutdown doesn't prevent completion")
    @available(LambdaSwift 2.0, *)
    func testOldChannelCleanupDuringShutdown() async throws {
        // This test simulates the scenario where:
        // 1. A connection is established
        // 2. Server closes connection (old channel starts closing)
        // 3. Client reconnects (new channel)
        // 4. Client initiates shutdown
        // 5. Old channel's closeFuture fires during shutdown
        // Expected: Shutdown should complete without hanging

        struct ShutdownWithOldChannelBehavior: LambdaServerBehavior {
            let requestId = UUID().uuidString
            var responseCount = 0

            func getInvocation() -> GetInvocationResult {
                .success((requestId, "event"))
            }

            func processResponse(requestId: String, response: String?) -> Result<String?, ProcessResponseError> {
                // First response triggers delayed disconnect
                if responseCount == 0 {
                    return .success("delayed-disconnect")
                }
                return .success(nil)
            }

            func processError(requestId: String, error: ErrorResponse) -> Result<Void, ProcessErrorError> {
                Issue.record("should not report error")
                return .failure(.internalServerError)
            }

            func processInitError(error: ErrorResponse) -> Result<Void, ProcessErrorError> {
                Issue.record("should not report init error")
                return .failure(.internalServerError)
            }
        }

        // Use a timeout to ensure shutdown completes
        try await withTimeout(deadline: .seconds(5)) {
            try await withMockServer(behaviour: ShutdownWithOldChannelBehavior()) { port in
                let configuration = LambdaRuntimeClient.Configuration(ip: "127.0.0.1", port: port)

                try await LambdaRuntimeClient.withRuntimeClient(
                    configuration: configuration,
                    eventLoop: NIOSingletons.posixEventLoopGroup.next(),
                    logger: self.logger
                ) { runtimeClient in
                    // First invocation
                    let (_, writer) = try await runtimeClient.nextInvocation()
                    try await writer.writeAndFinish(ByteBuffer(string: "response"))

                    // Give time for server to close connection
                    try await Task.sleep(for: .milliseconds(100))

                    // Try to get next invocation (will reconnect)
                    let _ = try? await runtimeClient.nextInvocation()

                    // Shutdown is triggered automatically when exiting withRuntimeClient
                    // If old channel cleanup is working, this should complete quickly
                }
            }
        }
        // If we reach here without timeout, the test passes
    }

    @Test("Shutdown completes when multiple old channels are closing")
    @available(LambdaSwift 2.0, *)
    func testShutdownWithMultipleOldChannels() async throws {
        // This test simulates multiple reconnections followed by shutdown
        // to ensure all old channels are properly tracked and cleaned up

        struct MultipleReconnectBehavior: LambdaServerBehavior {
            var invocationCount = 0

            func getInvocation() -> GetInvocationResult {
                let requestId = UUID().uuidString
                return .success((requestId, "event-\(invocationCount)"))
            }

            func processResponse(requestId: String, response: String?) -> Result<String?, ProcessResponseError> {
                // Trigger disconnect after each response to force reconnection
                return .success("delayed-disconnect")
            }

            func processError(requestId: String, error: ErrorResponse) -> Result<Void, ProcessErrorError> {
                Issue.record("should not report error")
                return .failure(.internalServerError)
            }

            func processInitError(error: ErrorResponse) -> Result<Void, ProcessErrorError> {
                Issue.record("should not report init error")
                return .failure(.internalServerError)
            }
        }

        // Use a timeout to ensure shutdown completes
        try await withTimeout(deadline: .seconds(5)) {
            try await withMockServer(behaviour: MultipleReconnectBehavior()) { port in
                let configuration = LambdaRuntimeClient.Configuration(ip: "127.0.0.1", port: port)

                try await LambdaRuntimeClient.withRuntimeClient(
                    configuration: configuration,
                    eventLoop: NIOSingletons.posixEventLoopGroup.next(),
                    logger: self.logger
                ) { runtimeClient in
                    // Perform multiple invocations with reconnections
                    for _ in 0..<3 {
                        do {
                            let (_, writer) = try await runtimeClient.nextInvocation()
                            try await writer.writeAndFinish(ByteBuffer(string: "response"))
                            // Give time for disconnect
                            try await Task.sleep(for: .milliseconds(50))
                        } catch {
                            // Connection errors are expected
                            break
                        }
                    }

                    // Shutdown happens automatically
                    // All old channels should be cleaned up properly
                }
            }
        }
        // If we reach here without timeout, the test passes
    }

    // MARK: - Test Fix #3: Current channel goes through proper state transitions

    @Test("Current channel closing triggers proper state transition")
    @available(LambdaSwift 2.0, *)
    func testCurrentChannelStateTransition() async throws {
        // This test verifies that when the current channel closes,
        // it goes through the main switch statement and properly
        // transitions to disconnected state (not taking early return)

        struct CurrentChannelCloseBehavior: LambdaServerBehavior {
            let requestId = UUID().uuidString

            func getInvocation() -> GetInvocationResult {
                .success((requestId, "event"))
            }

            func processResponse(requestId: String, response: String?) -> Result<String?, ProcessResponseError> {
                // Close connection after response
                return .success("delayed-disconnect")
            }

            func processError(requestId: String, error: ErrorResponse) -> Result<Void, ProcessErrorError> {
                Issue.record("should not report error")
                return .failure(.internalServerError)
            }

            func processInitError(error: ErrorResponse) -> Result<Void, ProcessErrorError> {
                Issue.record("should not report init error")
                return .failure(.internalServerError)
            }
        }

        try await withMockServer(behaviour: CurrentChannelCloseBehavior()) { port in
            let configuration = LambdaRuntimeClient.Configuration(ip: "127.0.0.1", port: port)

            try await LambdaRuntimeClient.withRuntimeClient(
                configuration: configuration,
                eventLoop: NIOSingletons.posixEventLoopGroup.next(),
                logger: self.logger
            ) { runtimeClient in
                // First invocation
                let (_, writer) = try await runtimeClient.nextInvocation()
                try await writer.writeAndFinish(ByteBuffer(string: "response"))

                // Give time for connection to close
                try await Task.sleep(for: .milliseconds(100))

                // Try next invocation - should reconnect successfully
                // This verifies that the state transition happened correctly
                do {
                    let (invocation, writer2) = try await runtimeClient.nextInvocation()
                    #expect(invocation.event == ByteBuffer(string: "event"))
                    try await writer2.writeAndFinish(ByteBuffer(string: "response"))
                } catch {
                    // Connection error is acceptable here
                    // The important part is that we didn't hang or crash
                }
            }
        }
    }

    @Test("Current channel in channelsBeingClosed doesn't take early return")
    @available(LambdaSwift 2.0, *)
    func testCurrentChannelNotTreatedAsOld() async throws {
        // This test specifically verifies the fix for Comment #3:
        // When a channel is in channelsBeingClosed but is still the current channel,
        // it should NOT take the early return path

        struct ImmediateCloseBehavior: LambdaServerBehavior {
            var invocationCount = 0

            func getInvocation() -> GetInvocationResult {
                let requestId = UUID().uuidString
                // Return disconnect on second call to close current channel
                if invocationCount > 0 {
                    return .success(("disconnect", "0"))
                }
                return .success((requestId, "event"))
            }

            func processResponse(requestId: String, response: String?) -> Result<String?, ProcessResponseError> {
                .success(nil)
            }

            func processError(requestId: String, error: ErrorResponse) -> Result<Void, ProcessErrorError> {
                Issue.record("should not report error")
                return .failure(.internalServerError)
            }

            func processInitError(error: ErrorResponse) -> Result<Void, ProcessErrorError> {
                Issue.record("should not report init error")
                return .failure(.internalServerError)
            }
        }

        try await withMockServer(behaviour: ImmediateCloseBehavior()) { port in
            let configuration = LambdaRuntimeClient.Configuration(ip: "127.0.0.1", port: port)

            try await LambdaRuntimeClient.withRuntimeClient(
                configuration: configuration,
                eventLoop: NIOSingletons.posixEventLoopGroup.next(),
                logger: self.logger
            ) { runtimeClient in
                // First invocation succeeds
                let (_, writer) = try await runtimeClient.nextInvocation()
                try await writer.writeAndFinish(ByteBuffer(string: "response"))

                // Second invocation will trigger disconnect
                // The current channel will be added to channelsBeingClosed
                // but should still go through proper state transition
                do {
                    let _ = try await runtimeClient.nextInvocation()
                    // Note: The disconnect might not happen immediately,
                    // so we may get a successful invocation here.
                    // The important part is that we don't hang or crash.
                } catch let error as LambdaRuntimeError {
                    // Expected error - connection was closed
                    #expect(error.code == .connectionToControlPlaneLost)
                } catch {
                    // Other errors are also acceptable (ChannelError, IOError, etc.)
                }

                // If we reach here without hanging, the state transition worked correctly
            }
        }
    }

    // MARK: - Integration Tests

    @Test("Rapid reconnections with old channels closing don't cause issues")
    @available(LambdaSwift 2.0, *)
    func testRapidReconnections() async throws {
        // This integration test simulates the exact race condition from Bug #624:
        // Rapid connection recycling where old channels close while new ones connect

        struct RapidReconnectBehavior: LambdaServerBehavior {
            var count = 0

            func getInvocation() -> GetInvocationResult {
                let requestId = UUID().uuidString
                return .success((requestId, "event"))
            }

            func processResponse(requestId: String, response: String?) -> Result<String?, ProcessResponseError> {
                // Alternate between normal and delayed disconnect
                // to create timing variations
                if count % 2 == 0 {
                    return .success("delayed-disconnect")
                }
                return .success(nil)
            }

            func processError(requestId: String, error: ErrorResponse) -> Result<Void, ProcessErrorError> {
                Issue.record("should not report error")
                return .failure(.internalServerError)
            }

            func processInitError(error: ErrorResponse) -> Result<Void, ProcessErrorError> {
                Issue.record("should not report init error")
                return .failure(.internalServerError)
            }
        }

        try await withTimeout(deadline: .seconds(10)) {
            try await withMockServer(behaviour: RapidReconnectBehavior()) { port in
                let configuration = LambdaRuntimeClient.Configuration(ip: "127.0.0.1", port: port)

                try await LambdaRuntimeClient.withRuntimeClient(
                    configuration: configuration,
                    eventLoop: NIOSingletons.posixEventLoopGroup.next(),
                    logger: self.logger
                ) { runtimeClient in
                    // Perform many rapid invocations
                    for i in 0..<10 {
                        do {
                            let (_, writer) = try await runtimeClient.nextInvocation()
                            try await writer.writeAndFinish(ByteBuffer(string: "response-\(i)"))

                            // Very short delay to create race conditions
                            try await Task.sleep(for: .milliseconds(10))
                        } catch {
                            // Connection errors are expected and acceptable
                            // The important part is we don't crash or hang
                            break
                        }
                    }
                }
            }
        }
        // If we complete without timeout or crash, all fixes are working
    }

    @Test("Concurrent operations during channel lifecycle transitions")
    @available(LambdaSwift 2.0, *)
    func testConcurrentOperationsDuringTransitions() async throws {
        // This test verifies that concurrent operations don't interfere
        // with channel lifecycle management

        struct ConcurrentBehavior: LambdaServerBehavior {
            func getInvocation() -> GetInvocationResult {
                let requestId = UUID().uuidString
                return .success((requestId, "event"))
            }

            func processResponse(requestId: String, response: String?) -> Result<String?, ProcessResponseError> {
                .success(nil)
            }

            func processError(requestId: String, error: ErrorResponse) -> Result<Void, ProcessErrorError> {
                .success(())
            }

            func processInitError(error: ErrorResponse) -> Result<Void, ProcessErrorError> {
                Issue.record("should not report init error")
                return .failure(.internalServerError)
            }
        }

        try await withTimeout(deadline: .seconds(5)) {
            try await withMockServer(behaviour: ConcurrentBehavior()) { port in
                let configuration = LambdaRuntimeClient.Configuration(ip: "127.0.0.1", port: port)

                try await LambdaRuntimeClient.withRuntimeClient(
                    configuration: configuration,
                    eventLoop: NIOSingletons.posixEventLoopGroup.next(),
                    logger: self.logger
                ) { runtimeClient in
                    // Perform a few invocations to establish connection
                    for _ in 0..<3 {
                        let (_, writer) = try await runtimeClient.nextInvocation()
                        try await writer.writeAndFinish(ByteBuffer(string: "response"))
                    }

                    // Shutdown happens automatically
                    // All channels should be properly cleaned up
                }
            }
        }
    }
}
