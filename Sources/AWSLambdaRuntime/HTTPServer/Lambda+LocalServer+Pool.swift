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
import DequeModule
import Synchronization

@available(LambdaSwift 2.0, *)
extension LambdaHTTPServer {

    /// A shared data structure to store the current invocation or response requests and the continuation objects.
    /// This data structure is shared between instances of the HTTPHandler
    /// (one instance to serve requests from the Lambda function and one instance to serve requests from the client invoking the lambda function).
    internal final class Pool<T>: AsyncSequence, AsyncIteratorProtocol, Sendable where T: Sendable {
        private let poolName: String
        internal init(name: String = "Pool") { self.poolName = name }

        typealias Element = T

        struct State {
            var buffer: Deque<T> = []
            var waitingForAny: CheckedContinuation<T, any Error>?
            var waitingForSpecific: [String: CheckedContinuation<T, any Error>] = [:]
        }

        private let lock = Mutex<State>(State())

        /// enqueue an element, or give it back immediately to the iterator if it is waiting for an element
        public func push(_ item: T) {
            let continuationToResume = self.lock.withLock { state -> CheckedContinuation<T, any Error>? in
                // First check if there's a waiting continuation that can handle this item

                // Check for FIFO waiter first
                if let continuation = state.waitingForAny {
                    state.waitingForAny = nil
                    return continuation
                }

                // Check for specific waiter
                if let response = item as? LocalServerResponse,
                    let requestId = response.requestId,
                    let continuation = state.waitingForSpecific.removeValue(forKey: requestId)
                {
                    return continuation
                }

                // No waiting continuation, add to buffer
                state.buffer.append(item)
                return nil
            }

            // Resume continuation outside the lock to prevent potential deadlocks
            continuationToResume?.resume(returning: item)
        }

        /// Unified next() method that handles both FIFO and requestId-specific waiting
        private func _next(for requestId: String?) async throws -> T {
            // exit if the task is cancelled
            guard !Task.isCancelled else {
                throw CancellationError()
            }

            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, any Error>) in
                    let nextAction: Result<T, PoolError>? = self.lock.withLock { state -> Result<T, PoolError>? in
                        if let requestId = requestId {
                            // Look for oldest (first) item for this requestId in buffer
                            if let index = state.buffer.firstIndex(where: { item in
                                if let response = item as? LocalServerResponse {
                                    return response.requestId == requestId
                                }
                                return false
                            }) {
                                let item = state.buffer.remove(at: index)
                                return .success(item)
                            } else {
                                // Check for conflicting waiters
                                if state.waitingForAny != nil {
                                    return .failure(PoolError(cause: .mixedWaitingModes))
                                }
                                if state.waitingForSpecific[requestId] != nil {
                                    return .failure(PoolError(cause: .duplicateRequestIdWait(requestId)))
                                }

                                // No matching item, wait for it
                                state.waitingForSpecific[requestId] = continuation
                                return nil
                            }
                        } else {
                            // FIFO mode - take first item
                            if let first = state.buffer.popFirst() {
                                return .success(first)
                            } else {
                                // Check for conflicting waiters
                                if !state.waitingForSpecific.isEmpty {
                                    return .failure(PoolError(cause: .mixedWaitingModes))
                                }
                                if state.waitingForAny != nil {
                                    return .failure(PoolError(cause: .nextCalledTwice(state.waitingForAny!)))
                                }

                                state.waitingForAny = continuation
                                return nil
                            }
                        }
                    }

                    switch nextAction {
                    case .success(let item):
                        continuation.resume(returning: item)
                    case .failure(let error):
                        if case let .nextCalledTwice(prevContinuation) = error.cause {
                            prevContinuation.resume(throwing: error)
                        }
                        continuation.resume(throwing: error)
                    case .none:
                        // do nothing - continuation is stored in state
                        break
                    }
                }
            } onCancel: {
                // Only remove THIS task's continuation
                let continuationToCancel = self.lock.withLock { state -> CheckedContinuation<T, any Error>? in
                    if let requestId = requestId {
                        // Remove only the continuation for this specific requestId
                        return state.waitingForSpecific.removeValue(forKey: requestId)
                    } else {
                        // Remove only the FIFO continuation
                        let cont = state.waitingForAny
                        state.waitingForAny = nil
                        return cont
                    }
                }
                
                continuationToCancel?.resume(throwing: CancellationError())
            }
        }

        /// Simple FIFO next() method - used by AsyncIteratorProtocol
        func next() async throws -> T? {
            try await _next(for: nil)
        }

        /// RequestId-specific next() method for LocalServerResponse - NOT part of AsyncIteratorProtocol
        func next(for requestId: String) async throws -> T {
            try await _next(for: requestId)
        }

        func makeAsyncIterator() -> Pool {
            self
        }

        /// Cancel all waiting continuations - used during server shutdown
        func cancelAll() {
            let continuationsToCancel = self.lock.withLock { state -> [CheckedContinuation<T, any Error>] in
                var toCancel: [CheckedContinuation<T, any Error>] = []
                
                if let continuation = state.waitingForAny {
                    toCancel.append(continuation)
                    state.waitingForAny = nil
                }
                
                for continuation in state.waitingForSpecific.values {
                    toCancel.append(continuation)
                }
                state.waitingForSpecific.removeAll()
                
                return toCancel
            }
            
            // Resume all continuations outside the lock
            for continuation in continuationsToCancel {
                continuation.resume(throwing: CancellationError())
            }
        }

        struct PoolError: Error {
            let cause: Cause
            var message: String {
                switch self.cause {
                case .nextCalledTwice:
                    return "Concurrent invocations to next(). This is not allowed."
                case .duplicateRequestIdWait(let requestId):
                    return "Already waiting for requestId: \(requestId)"
                case .mixedWaitingModes:
                    return "Cannot mix FIFO waiting (next()) with specific waiting (next(for:))"
                }
            }

            enum Cause {
                case nextCalledTwice(CheckedContinuation<T, any Error>)
                case duplicateRequestIdWait(String)
                case mixedWaitingModes
            }
        }
    }
}
#endif
