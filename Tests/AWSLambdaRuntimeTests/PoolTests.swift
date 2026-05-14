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

#if LocalServerSupport

import NIOCore
import Testing

@testable import AWSLambdaRuntime

struct PoolTests {

    @Test
    @available(LambdaSwift 2.0, *)
    func testBasicPushAndIteration() async throws {
        let pool = LambdaHTTPServer.Pool<String>()

        // Push values
        pool.push("first")
        pool.push("second")

        // Iterate and verify order
        var values = [String]()
        for try await value in pool {
            values.append(value)
            if values.count == 2 { break }
        }

        #expect(values == ["first", "second"])
    }

    @Test
    @available(LambdaSwift 2.0, *)
    func testPoolCancellation() async throws {
        let pool = LambdaHTTPServer.Pool<String>()

        // Create a task that will be cancelled
        let task = Task {
            for try await _ in pool {
                Issue.record("Should not receive any values after cancellation")
            }
        }

        // Cancel the task immediately
        task.cancel()

        // This should complete without receiving any values
        do {
            try await task.value
        } catch is CancellationError {
            // this might happen depending on the order on which the cancellation is handled
        }
    }

    @Test
    @available(LambdaSwift 2.0, *)
    func testConcurrentPushAndIteration() async throws {
        let pool = LambdaHTTPServer.Pool<Int>()
        let iterations = 1000

        // Start consumer task first
        let consumer = Task { @Sendable in
            var receivedValues = Set<Int>()
            var count = 0
            for try await value in pool {
                receivedValues.insert(value)
                count += 1
                if count >= iterations { break }
            }
            return receivedValues
        }

        // Create multiple producer tasks
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<iterations {
                group.addTask {
                    pool.push(i)
                }
            }
            try await group.waitForAll()
        }

        // Wait for consumer to complete
        let receivedValues = try await consumer.value

        // Verify all values were received exactly once
        #expect(receivedValues.count == iterations)
        #expect(Set(0..<iterations) == receivedValues)
    }

    @Test
    @available(LambdaSwift 2.0, *)
    func testPushToWaitingConsumer() async throws {
        let pool = LambdaHTTPServer.Pool<String>()
        let expectedValue = "test value"

        // Start a consumer that will wait for a value
        let consumer = Task {
            for try await value in pool {
                #expect(value == expectedValue)
                break
            }
        }

        // Give consumer time to start waiting
        try await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds

        // Push a value
        pool.push(expectedValue)

        // Wait for consumer to complete
        try await consumer.value
    }

    @Test
    @available(LambdaSwift 2.0, *)
    func testStressTest() async throws {
        let pool = LambdaHTTPServer.Pool<Int>()
        let producerCount = 10
        let messagesPerProducer = 1000

        // Start consumer
        let consumer = Task { @Sendable in
            var receivedValues = [Int]()
            var count = 0
            for try await value in pool {
                receivedValues.append(value)
                count += 1
                if count >= producerCount * messagesPerProducer { break }
            }
            return receivedValues
        }

        // Create multiple producers
        try await withThrowingTaskGroup(of: Void.self) { group in
            for p in 0..<producerCount {
                group.addTask {
                    for i in 0..<messagesPerProducer {
                        pool.push(p * messagesPerProducer + i)
                    }
                }
            }
            try await group.waitForAll()
        }

        // Wait for consumer to complete
        let receivedValues = try await consumer.value

        // Verify we received all values
        #expect(receivedValues.count == producerCount * messagesPerProducer)
        #expect(Set(receivedValues).count == producerCount * messagesPerProducer)
    }

    @Test
    @available(LambdaSwift 2.0, *)
    func testConcurrentNext() async throws {
        let pool = LambdaHTTPServer.Pool<String>()

        // Create two tasks that will both wait for elements to be available
        let error = await #expect(throws: LambdaHTTPServer.Pool<String>.PoolError.self) {
            try await withThrowingTaskGroup(of: Void.self) { group in

                // one of the two task will throw a PoolError

                group.addTask {
                    for try await _ in pool {
                    }
                    Issue.record("Loop 1 should not complete")
                }

                group.addTask {
                    for try await _ in pool {
                    }
                    Issue.record("Loop 2 should not complete")
                }
                try await group.waitForAll()
            }
        }

        // Verify it's the correct error cause
        if case .nextCalledTwice = error?.cause {
            // This is the expected error
        } else {
            Issue.record("Expected nextCalledTwice error, got: \(String(describing: error?.cause))")
        }
    }

    // MARK: - Invariant Tests for RequestId-specific functionality

    @Test
    @available(LambdaSwift 2.0, *)
    func testRequestIdSpecificNext() async throws {
        let pool = LambdaHTTPServer.Pool<LambdaHTTPServer.LocalServerResponse>()

        // Push responses with different requestIds
        pool.push(LambdaHTTPServer.LocalServerResponse(id: "req1", body: ByteBuffer(string: "data1")))
        pool.push(LambdaHTTPServer.LocalServerResponse(id: "req2", body: ByteBuffer(string: "data2")))
        pool.push(LambdaHTTPServer.LocalServerResponse(id: "req1", body: ByteBuffer(string: "data3")))

        // Get specific responses
        let response1 = try await pool.next(for: "req1")
        #expect(response1.requestId == "req1")
        #expect(String(buffer: response1.body!) == "data1")

        let response2 = try await pool.next(for: "req2")
        #expect(response2.requestId == "req2")
        #expect(String(buffer: response2.body!) == "data2")

        let response3 = try await pool.next(for: "req1")
        #expect(response3.requestId == "req1")
        #expect(String(buffer: response3.body!) == "data3")
    }

    @Test
    @available(LambdaSwift 2.0, *)
    func testStreamingResponsesWithSameRequestId() async throws {
        let pool = LambdaHTTPServer.Pool<LambdaHTTPServer.LocalServerResponse>()
        let requestId = "streaming-req"

        let chunks = try await withThrowingTaskGroup(of: [String].self) { group in
            // Start consumer task
            group.addTask {
                var chunks: [String] = []
                var isComplete = false

                while !isComplete {
                    let response = try await pool.next(for: requestId)
                    if let body = response.body {
                        chunks.append(String(buffer: body))
                    }
                    if response.final {
                        isComplete = true
                    }
                }
                return chunks
            }

            // Start producer task
            group.addTask {
                // Give consumer time to start waiting
                try await Task.sleep(nanoseconds: 10_000_000)  // 0.01 seconds

                // Push multiple chunks for the same requestId
                pool.push(
                    LambdaHTTPServer.LocalServerResponse(
                        id: requestId,
                        body: ByteBuffer(string: "chunk1"),
                        final: false
                    )
                )
                pool.push(
                    LambdaHTTPServer.LocalServerResponse(
                        id: requestId,
                        body: ByteBuffer(string: "chunk2"),
                        final: false
                    )
                )
                pool.push(
                    LambdaHTTPServer.LocalServerResponse(id: requestId, body: ByteBuffer(string: "chunk3"), final: true)
                )

                return []  // Producer doesn't return chunks
            }

            // Wait for consumer to complete and return its result
            for try await result in group {
                if !result.isEmpty {
                    group.cancelAll()
                    return result
                }
            }
            return []
        }

        #expect(chunks == ["chunk1", "chunk2", "chunk3"])
    }

    @Test
    @available(LambdaSwift 2.0, *)
    func testMixedWaitingModesError() async throws {
        let pool = LambdaHTTPServer.Pool<LambdaHTTPServer.LocalServerResponse>()

        let error = await #expect(throws: LambdaHTTPServer.Pool<LambdaHTTPServer.LocalServerResponse>.PoolError.self) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                // Start a FIFO consumer
                group.addTask {
                    for try await _ in pool {
                        // This should block waiting for any item
                    }
                }

                // Start a requestId-specific consumer after a delay
                group.addTask {
                    // Give FIFO task time to start waiting
                    try await Task.sleep(nanoseconds: 10_000_000)  // 0.01 seconds

                    // Try to use requestId-specific next - should fail with mixedWaitingModes
                    _ = try await pool.next(for: "req1")
                }

                // Wait for the first task to complete (which should be the error)
                try await group.next()
                group.cancelAll()
            }
        }

        // Verify it's the correct error cause
        if case .mixedWaitingModes = error?.cause {
            // This is the expected error
        } else {
            Issue.record("Expected mixedWaitingModes error, got: \(String(describing: error?.cause))")
        }
    }

    @Test
    @available(LambdaSwift 2.0, *)
    func testMixedWaitingModesErrorReverse() async throws {
        let pool = LambdaHTTPServer.Pool<LambdaHTTPServer.LocalServerResponse>()

        let error = await #expect(throws: LambdaHTTPServer.Pool<LambdaHTTPServer.LocalServerResponse>.PoolError.self) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                // Start a requestId-specific consumer
                group.addTask {
                    _ = try await pool.next(for: "req1")
                }

                // Start a FIFO consumer after a delay
                group.addTask {
                    // Give specific task time to start waiting
                    try await Task.sleep(nanoseconds: 10_000_000)  // 0.01 seconds

                    // Try to use FIFO next - should fail with mixedWaitingModes
                    for try await _ in pool {
                        break
                    }
                }

                // Wait for the first task to complete (which should be the error)
                try await group.next()
                group.cancelAll()
            }
        }

        // Verify it's the correct error cause
        if case .mixedWaitingModes = error?.cause {
            // This is the expected error
        } else {
            Issue.record("Expected mixedWaitingModes error, got: \(String(describing: error?.cause))")
        }
    }

    @Test
    @available(LambdaSwift 2.0, *)
    func testDuplicateRequestIdWaitError() async throws {
        let pool = LambdaHTTPServer.Pool<LambdaHTTPServer.LocalServerResponse>()

        let error = await #expect(throws: LambdaHTTPServer.Pool<LambdaHTTPServer.LocalServerResponse>.PoolError.self) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                // Start first consumer waiting for specific requestId
                group.addTask {
                    _ = try await pool.next(for: "req1")
                }

                // Start second consumer for same requestId after a delay
                group.addTask {
                    // Give first task time to start waiting
                    try await Task.sleep(nanoseconds: 10_000_000)  // 0.01 seconds

                    // Try to wait for the same requestId - should fail
                    _ = try await pool.next(for: "req1")
                }

                // Wait for the first task to complete (which should be the error)
                try await group.next()
                group.cancelAll()
            }
        }

        // Verify it's the correct error cause and requestId
        if case let .duplicateRequestIdWait(requestId) = error?.cause {
            #expect(requestId == "req1")
        } else {
            Issue.record("Expected duplicateRequestIdWait error, got: \(String(describing: error?.cause))")
        }
    }

    @Test
    @available(LambdaSwift 2.0, *)
    func testConcurrentRequestIdConsumers() async throws {
        let pool = LambdaHTTPServer.Pool<LambdaHTTPServer.LocalServerResponse>()

        let results = try await withThrowingTaskGroup(of: (String, String).self) { group in
            // Start multiple consumers for different requestIds
            group.addTask {
                let response = try await pool.next(for: "req1")
                return ("req1", String(buffer: response.body!))
            }

            group.addTask {
                let response = try await pool.next(for: "req2")
                return ("req2", String(buffer: response.body!))
            }

            group.addTask {
                let response = try await pool.next(for: "req3")
                return ("req3", String(buffer: response.body!))
            }

            // Start producer task
            group.addTask {
                // Give tasks time to start waiting
                try await Task.sleep(nanoseconds: 10_000_000)  // 0.01 seconds

                // Push responses in different order
                pool.push(LambdaHTTPServer.LocalServerResponse(id: "req3", body: ByteBuffer(string: "data3")))
                pool.push(LambdaHTTPServer.LocalServerResponse(id: "req1", body: ByteBuffer(string: "data1")))
                pool.push(LambdaHTTPServer.LocalServerResponse(id: "req2", body: ByteBuffer(string: "data2")))

                return ("producer", "")  // Producer doesn't return meaningful data
            }

            // Collect results from consumers
            var consumerResults: [String: String] = [:]
            for try await (requestId, data) in group {
                if requestId != "producer" {
                    consumerResults[requestId] = data
                }
                if consumerResults.count == 3 {
                    group.cancelAll()
                    break
                }
            }
            return consumerResults
        }

        // Verify each consumer gets the correct response
        #expect(results["req1"] == "data1")
        #expect(results["req2"] == "data2")
        #expect(results["req3"] == "data3")
    }

    @Test
    @available(LambdaSwift 2.0, *)
    func testCancellationCleansUpAllContinuations() async throws {
        let pool = LambdaHTTPServer.Pool<LambdaHTTPServer.LocalServerResponse>()

        // Test that cancellation properly cleans up all continuations
        await #expect(throws: CancellationError.self) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                // Start multiple consumers for different requestIds
                group.addTask {
                    _ = try await pool.next(for: "req1")
                }

                group.addTask {
                    _ = try await pool.next(for: "req2")
                }

                group.addTask {
                    _ = try await pool.next(for: "req3")
                }

                // Give tasks time to start waiting then cancel all
                try await Task.sleep(nanoseconds: 10_000_000)  // 0.01 seconds
                group.cancelAll()

                try await group.waitForAll()
            }
        }

        // Pool should be back to clean state - verify by pushing and consuming normally
        pool.push(LambdaHTTPServer.LocalServerResponse(id: "new-req", body: ByteBuffer(string: "new-data")))
        let response = try await pool.next(for: "new-req")
        #expect(String(buffer: response.body!) == "new-data")
    }

    @Test
    @available(LambdaSwift 2.0, *)
    func testBufferOrderingWithRequestIds() async throws {
        let pool = LambdaHTTPServer.Pool<LambdaHTTPServer.LocalServerResponse>()

        // Push multiple responses for the same requestId
        pool.push(LambdaHTTPServer.LocalServerResponse(id: "req1", body: ByteBuffer(string: "first")))
        pool.push(LambdaHTTPServer.LocalServerResponse(id: "req2", body: ByteBuffer(string: "other")))
        pool.push(LambdaHTTPServer.LocalServerResponse(id: "req1", body: ByteBuffer(string: "second")))
        pool.push(LambdaHTTPServer.LocalServerResponse(id: "req1", body: ByteBuffer(string: "third")))

        // Consume in order - should get FIFO order for the same requestId
        let first = try await pool.next(for: "req1")
        #expect(String(buffer: first.body!) == "first")

        let second = try await pool.next(for: "req1")
        #expect(String(buffer: second.body!) == "second")

        let other = try await pool.next(for: "req2")
        #expect(String(buffer: other.body!) == "other")

        let third = try await pool.next(for: "req1")
        #expect(String(buffer: third.body!) == "third")
    }
}
#endif  // trait
