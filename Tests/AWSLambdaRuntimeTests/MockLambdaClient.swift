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

import AWSLambdaRuntime
import Logging
import NIOCore
import NIOHTTP1

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@available(LambdaSwift 2.0, *)
struct MockLambdaWriter: LambdaRuntimeClientResponseStreamWriter {
    var underlying: MockLambdaClient

    init(underlying: MockLambdaClient) {
        self.underlying = underlying
    }

    func write(_ buffer: ByteBuffer, hasCustomHeaders: Bool = false) async throws {
        try await self.underlying.write(buffer, hasCustomHeaders: hasCustomHeaders)
    }

    func finish() async throws {
        try await self.underlying.finish()
    }

    func writeAndFinish(_ buffer: ByteBuffer) async throws {
        try await self.underlying.write(buffer)
        try await self.underlying.finish()
    }

    func reportError(_ error: any Error) async throws {
        await self.underlying.reportError(error)
    }
}

enum LambdaError: Error, Equatable {
    case cannotCallNextEndpointWhenAlreadyWaitingForEvent
    case cannotCallNextEndpointWhenAlreadyProcessingAnEvent
    case cannotReportResultWhenNoEventHasBeenProcessed
    case cancelError
    case handlerError
}

@available(LambdaSwift 2.0, *)
final actor MockLambdaClient: LambdaRuntimeClientProtocol {
    typealias Writer = MockLambdaWriter

    @available(LambdaSwift 2.0, *)
    private struct StateMachine {
        @available(LambdaSwift 2.0, *)
        private enum State {
            // The Lambda has just started, or an event has finished processing and the runtime is ready to receive more events.
            // Expecting a next() call by the runtime.
            case initialState

            // The next endpoint has been called but no event has arrived yet.
            case waitingForNextEvent(eventArrivedHandler: CheckedContinuation<Invocation, any Error>)

            // The handler is processing the event. Buffers written to the writer are accumulated.
            case handlerIsProcessing(
                accumulatedResponse: [ByteBuffer],
                eventProcessedHandler: CheckedContinuation<ByteBuffer, any Error>
            )
        }

        private var state: State = .initialState

        // Queue incoming events if the runtime is busy handling an event.
        private var eventQueue = [Event]()

        @available(LambdaSwift 2.0, *)
        enum InvokeAction {
            // The next endpoint is waiting for an event. Deliver this newly arrived event to it.
            case readyToProcess(_ eventArrivedHandler: CheckedContinuation<Invocation, any Error>)

            // The next endpoint has not been called yet. This event has been added to the queue.
            case wait
        }

        @available(LambdaSwift 2.0, *)
        enum NextAction {
            // There is an event available to be processed.
            case readyToProcess(Invocation)

            // No events available yet. Wait for an event to arrive.
            case wait

            case fail(LambdaError)
        }

        @available(LambdaSwift 2.0, *)
        enum CancelNextAction {
            case none

            case cancelContinuation(CheckedContinuation<Invocation, any Error>)
        }

        enum ResultAction {
            case readyForMore

            case fail(LambdaError)
        }

        enum FailProcessingAction {
            case none

            case throwContinuation(CheckedContinuation<ByteBuffer, any Error>)
        }

        mutating func next(_ eventArrivedHandler: CheckedContinuation<Invocation, any Error>) -> NextAction {
            switch self.state {
            case .initialState:
                if self.eventQueue.isEmpty {
                    // No event available yet -- store the continuation for the next invoke() call.
                    self.state = .waitingForNextEvent(eventArrivedHandler: eventArrivedHandler)
                    return .wait
                } else {
                    // An event is already waiting to be processed
                    let event = self.eventQueue.removeFirst()  // TODO: use Deque

                    self.state = .handlerIsProcessing(
                        accumulatedResponse: [],
                        eventProcessedHandler: event.eventProcessedHandler
                    )
                    return .readyToProcess(event.invocation)
                }
            case .waitingForNextEvent:
                return .fail(.cannotCallNextEndpointWhenAlreadyWaitingForEvent)
            case .handlerIsProcessing:
                return .fail(.cannotCallNextEndpointWhenAlreadyProcessingAnEvent)
            }
        }

        mutating func invoke(_ event: Event) -> InvokeAction {
            switch self.state {
            case .initialState, .handlerIsProcessing:
                // next() hasn't been called yet. Add to the event queue.
                self.eventQueue.append(event)
                return .wait
            case .waitingForNextEvent(let eventArrivedHandler):
                // The runtime is already waiting for an event
                self.state = .handlerIsProcessing(
                    accumulatedResponse: [],
                    eventProcessedHandler: event.eventProcessedHandler
                )
                return .readyToProcess(eventArrivedHandler)
            }
        }

        mutating func writeResult(buffer: ByteBuffer, hasCustomHeaders: Bool = false) -> ResultAction {
            switch self.state {
            case .handlerIsProcessing(var accumulatedResponse, let eventProcessedHandler):
                accumulatedResponse.append(buffer)
                self.state = .handlerIsProcessing(
                    accumulatedResponse: accumulatedResponse,
                    eventProcessedHandler: eventProcessedHandler
                )
                return .readyForMore
            case .initialState, .waitingForNextEvent:
                return .fail(.cannotReportResultWhenNoEventHasBeenProcessed)
            }
        }

        mutating func finish() throws {
            switch self.state {
            case .handlerIsProcessing(let accumulatedResponse, let eventProcessedHandler):
                let finalResult: ByteBuffer = accumulatedResponse.reduce(ByteBuffer()) { (accumulated, current) in
                    var accumulated = accumulated
                    accumulated.writeBytes(current.readableBytesView)
                    return accumulated
                }

                eventProcessedHandler.resume(returning: finalResult)
                // reset back to the initial state
                self.state = .initialState
            case .initialState, .waitingForNextEvent:
                throw LambdaError.cannotReportResultWhenNoEventHasBeenProcessed
            }
        }

        mutating func cancelNext() -> CancelNextAction {
            switch self.state {
            case .initialState, .handlerIsProcessing:
                return .none
            case .waitingForNextEvent(let eventArrivedHandler):
                self.state = .initialState
                return .cancelContinuation(eventArrivedHandler)
            }
        }

        mutating func failProcessing() -> FailProcessingAction {
            switch self.state {
            case .initialState, .waitingForNextEvent:
                // Cannot report an error for an event if the event is not currently being processed.
                fatalError()
            case .handlerIsProcessing(_, let eventProcessedHandler):
                return .throwContinuation(eventProcessedHandler)
            }
        }
    }

    private var stateMachine = StateMachine()

    @available(LambdaSwift 2.0, *)
    struct Event {
        let invocation: Invocation
        let eventProcessedHandler: CheckedContinuation<ByteBuffer, any Error>
    }

    func invoke(event: ByteBuffer, requestID: String = UUID().uuidString) async throws -> ByteBuffer {
        try await withCheckedThrowingContinuation { eventProcessedHandler in
            do {
                let metadata = try InvocationMetadata(
                    headers: .init([
                        ("Lambda-Runtime-Aws-Request-Id", "\(requestID)"),  // arbitrary values
                        ("Lambda-Runtime-Deadline-Ms", "100"),
                        ("Lambda-Runtime-Invoked-Function-Arn", "100"),
                    ])
                )
                let invocation = Invocation(metadata: metadata, event: event)

                let invokeAction = self.stateMachine.invoke(
                    Event(
                        invocation: invocation,
                        eventProcessedHandler: eventProcessedHandler
                    )
                )

                switch invokeAction {
                case .readyToProcess(let eventArrivedHandler):
                    // nextInvocation had been called earlier and is currently waiting for an event; deliver
                    eventArrivedHandler.resume(returning: invocation)
                case .wait:
                    // The event has been added to the event queue; wait for it to be picked up
                    break
                }
            } catch {
                eventProcessedHandler.resume(throwing: error)
            }
        }
    }

    func nextInvocation() async throws -> (Invocation, Writer) {
        try await withTaskCancellationHandler {
            let invocation = try await withCheckedThrowingContinuation { eventArrivedHandler in
                switch self.stateMachine.next(eventArrivedHandler) {
                case .readyToProcess(let event):
                    eventArrivedHandler.resume(returning: event)
                case .fail(let error):
                    eventArrivedHandler.resume(throwing: error)
                case .wait:
                    break
                }
            }
            return (invocation, Writer(underlying: self))
        } onCancel: {
            Task {
                await self.cancelNextInvocation()
            }
        }
    }

    private func cancelNextInvocation() {
        switch self.stateMachine.cancelNext() {
        case .none:
            break
        case .cancelContinuation(let continuation):
            continuation.resume(throwing: LambdaError.cancelError)
        }
    }

    func write(_ buffer: ByteBuffer, hasCustomHeaders: Bool = false) async throws {
        switch self.stateMachine.writeResult(buffer: buffer, hasCustomHeaders: hasCustomHeaders) {
        case .readyForMore:
            break
        case .fail(let error):
            throw error
        }
    }

    func finish() async throws {
        try self.stateMachine.finish()
    }

    func reportError(_ error: any Error) {
        switch self.stateMachine.failProcessing() {
        case .none:
            break
        case .throwContinuation(let continuation):
            continuation.resume(throwing: error)
        }
    }
}
