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
import Testing
import NIOCore
import Synchronization

@testable import AWSLambdaRuntime

@Suite("LocalServer Pool Cancellation Tests")
struct LocalServerPoolCancellationTests {
    
    /// Test that reproduces Issue #2: Cancellation handler removes ALL continuations
    ///
    /// This test demonstrates the bug where cancelling one task waiting in `waitingForSpecific`
    /// causes ALL other waiting tasks to also receive CancellationError, even though they
    /// weren't cancelled.
    ///
    /// Expected behavior: Only the cancelled task should receive CancellationError
    /// Actual behavior: ALL waiting tasks receive CancellationError
    @Test("Cancelling one task should not affect other waiting tasks")
    @available(LambdaSwift 2.0, *)
    func testCancellationOnlyAffectsOwnTask() async throws {
        #if compiler(>=6.0)
        let pool = LambdaHTTPServer.Pool<TestItem>(name: "Test Pool")
        
        let cancelledFlags = Mutex<[Bool]>([false, false, false])
        
        // Create 3 tasks waiting for different requestIds
        let task1 = Task { @Sendable in
            do {
                _ = try await pool.next(for: "request-1")
            } catch is CancellationError {
                cancelledFlags.withLock { $0[0] = true }
            }
        }
        
        let task2 = Task { @Sendable in
            do {
                _ = try await pool.next(for: "request-2")
            } catch is CancellationError {
                cancelledFlags.withLock { $0[1] = true }
            }
        }
        
        let task3 = Task { @Sendable in
            do {
                _ = try await pool.next(for: "request-3")
            } catch is CancellationError {
                cancelledFlags.withLock { $0[2] = true }
            }
        }
        
        // Let tasks register their continuations
        try await Task.sleep(for: .milliseconds(100))
        
        // Cancel only task 2
        task2.cancel()
        
        // Give cancellation time to propagate
        try await Task.sleep(for: .milliseconds(100))
        
        // Check cancellation status
        let flags = cancelledFlags.withLock { $0 }
        
        #expect(flags[1] == true, "Task 2 should be cancelled")
        
        // With the bug, task1 and task3 will also be cancelled
        if flags[0] || flags[2] {
            Issue.record("BUG REPRODUCED: Other tasks were cancelled when only task 2 should have been cancelled")
        }
        
        #expect(flags[0] == false, "Task 1 should NOT be cancelled")
        #expect(flags[2] == false, "Task 3 should NOT be cancelled")
        
        // Clean up - cancel all tasks
        task1.cancel()
        task2.cancel()
        task3.cancel()
        
        _ = await task1.result
        _ = await task2.result
        _ = await task3.result
        
        #else
        throw XCTSkip("This test requires Swift 6.0 or later")
        #endif
    }
    
    /// Test concurrent invocations with one being cancelled
    ///
    /// This simulates the real-world scenario where multiple clients invoke the Lambda
    /// function simultaneously, and one client's connection drops.
    @Test("Multiple concurrent invocations with one cancellation")
    @available(LambdaSwift 2.0, *)
    func testConcurrentInvocationsWithCancellation() async throws {
        #if compiler(>=6.0)
        
        try await withThrowingTaskGroup(of: Void.self) { group in
            // Timeout task
            group.addTask {
                try await Task.sleep(for: .seconds(10))
                throw TestError.timeout
            }
            
            // Main test task
            group.addTask {
                let pool = LambdaHTTPServer.Pool<TestItem>(name: "Concurrent Test Pool")
                
                let cancelledCount = Mutex<Int>(0)
                
                // Spawn 5 concurrent tasks waiting for different requestIds
                var tasks: [Task<Void, any Error>] = []
                for i in 1...5 {
                    let task = Task { @Sendable in
                        do {
                            _ = try await pool.next(for: "request-\(i)")
                        } catch is CancellationError {
                            cancelledCount.withLock { $0 += 1 }
                        }
                    }
                    tasks.append(task)
                }
                
                // Let all tasks register their continuations
                try await Task.sleep(for: .milliseconds(200))
                
                // Cancel task 3 (index 2)
                tasks[2].cancel()
                
                // Give cancellation time to propagate
                try await Task.sleep(for: .milliseconds(200))
                
                // Check how many tasks were cancelled
                let count = cancelledCount.withLock { $0 }
                
                // Expected: 1 cancelled
                // Actual (with bug): 5 cancelled
                if count > 1 {
                    Issue.record("BUG REPRODUCED: \(count) tasks were cancelled, but only 1 should have been cancelled")
                }
                
                #expect(count == 1, "Only 1 task should be cancelled, but \(count) were cancelled")
                
                // Clean up - cancel all remaining tasks
                for task in tasks {
                    task.cancel()
                }
                
                for task in tasks {
                    _ = await task.result
                }
            }
            
            // Wait for first task to complete (should be main test, not timeout)
            try await group.next()
            group.cancelAll()
        }
        
        #else
        throw XCTSkip("This test requires Swift 6.0 or later")
        #endif
    }
    
    /// Test that FIFO mode doesn't have the same issue
    ///
    /// FIFO mode only allows one waiter at a time, so this bug shouldn't affect it.
    @Test("FIFO mode cancellation works correctly")
    @available(LambdaSwift 2.0, *)
    func testFIFOModeCancellation() async throws {
        #if compiler(>=6.0)
        let pool = LambdaHTTPServer.Pool<TestItem>(name: "FIFO Test Pool")
        
        try await withThrowingTaskGroup(of: Void.self) { group in
            
            // Timeout
            group.addTask {
                try await Task.sleep(for: .seconds(10))
                throw TestError.timeout
            }
            
            // Main test
            group.addTask {
                let task = Task { @Sendable in
                    do {
                        guard let item = try await pool.next() else {
                            return "error: nil item"
                        }
                        return "success: \(item.id)"
                    } catch is CancellationError {
                        return "cancelled"
                    } catch {
                        return "error: \(error)"
                    }
                }
                
                // Let task register continuation
                try await Task.sleep(for: .milliseconds(100))
                
                // Cancel the task
                task.cancel()
                
                // Wait for result
                let result = await task.value
                
                #expect(result == "cancelled", "Task should be cancelled")
            }
            
            try await group.next()
            group.cancelAll()
        }
        #else
        throw XCTSkip("This test requires Swift 6.0 or later")
        #endif
    }
}

// MARK: - Test Helpers

extension LocalServerPoolCancellationTests {
    
    struct TestItem: Sendable {
        let id: String
        let data: String
    }
    
    enum TestResult: Sendable {
        case success(String)
        case cancelled(String)
        case error(String, any Error)
    }
    
    enum TestError: Error {
        case timeout
    }
}

// Make TestItem conform to LocalServerResponse protocol if needed
extension LocalServerPoolCancellationTests.TestItem {
    var requestId: String? { id }
}

#endif
