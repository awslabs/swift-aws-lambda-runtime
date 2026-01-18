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

#if ManagedRuntimeSupport

import Logging
import NIOCore
import Synchronization

// This is our guardian to ensure only one LambdaManagedRuntime is running at the time
// We use an Atomic here to ensure thread safety
@available(LambdaSwift 2.0, *)
private let _isLambdaManagedRuntimeRunning = Atomic<Bool>(false)

@available(LambdaSwift 2.0, *)
public final class LambdaManagedRuntime<Handler>: Sendable where Handler: StreamingLambdaHandler & Sendable {

    @usableFromInline
    let logger: Logger

    @usableFromInline
    let eventLoop: EventLoop

    @usableFromInline
    let handler: Handler

    public init(
        handler: Handler,
        eventLoop: EventLoop = Lambda.defaultEventLoop,
        logger: Logger = Logger(label: "LambdaManagedRuntime")
    ) {
        self.handler = handler
        self.eventLoop = eventLoop

        // by setting the log level here, we understand it can not be changed dynamically at runtime
        // developers have to wait for AWS Lambda to dispose and recreate a runtime environment to pickup a change
        // this approach is less flexible but more performant than reading the value of the environment variable at each invocation
        var log = logger

        // use the LOG_LEVEL environment variable to set the log level.
        // if the environment variable is not set, use the default log level from the logger provided
        log.logLevel = Lambda.env("LOG_LEVEL").flatMap { .init(rawValue: $0) } ?? logger.logLevel

        self.logger = log
        self.logger.debug("LambdaManagedRuntime initialized")
    }

    #if !ServiceLifecycleSupport
    public func run() async throws {
        try await self._run()
    }
    #endif

    /// Starts the Runtime Interface Client (RIC), i.e. the loop that will poll events,
    /// dispatch them to the Handler and push back results or errors.
    /// This function makes sure only one run() is called at a time
    internal func _run() async throws {

        // we use an atomic global variable to ensure only one LambdaRuntime is running at the time
        let (_, original) = _isLambdaManagedRuntimeRunning.compareExchange(
            expected: false,
            desired: true,
            ordering: .acquiringAndReleasing
        )

        // if the original value was already true, run() is already running
        if original {
            throw LambdaRuntimeError(code: .runtimeCanOnlyBeStartedOnce)
        }

        defer {
            _isLambdaManagedRuntimeRunning.store(false, ordering: .releasing)
        }

        // are we running inside an AWS Lambda runtime environment ?
        // AWS_LAMBDA_RUNTIME_API is set when running on Lambda
        // https://docs.aws.amazon.com/lambda/latest/dg/runtimes-api.html
        if let runtimeEndpoint = Lambda.env("AWS_LAMBDA_RUNTIME_API") {

            // Get the max concurrency authorized by user when running on
            // Lambda Managed Instances
            // See:
            // - https://docs.aws.amazon.com/lambda/latest/dg/lambda-managed-instances.html#lambda-managed-instances-concurrency-model
            // - https://docs.aws.amazon.com/lambda/latest/dg/configuration-envvars.html
            //
            // and the NodeJS implementation
            // https://github.com/aws/aws-lambda-nodejs-runtime-interface-client/blob/a4560c87426fa0a34756296a30d7add1388e575c/src/utils/env.ts#L34
            // https://github.com/aws/aws-lambda-nodejs-runtime-interface-client/blob/a4560c87426fa0a34756296a30d7add1388e575c/src/worker/ignition.ts#L12
            let maxConcurrency = Int(Lambda.env("AWS_LAMBDA_MAX_CONCURRENCY") ?? "1") ?? 1

            // when max concurrency is 1, do not pay the overhead of launching a Task
            if maxConcurrency <= 1 {
                self.logger.trace("Starting the Runtime Interface Client")
                try await LambdaRuntime.startRuntimeInterfaceClient(
                    endpoint: runtimeEndpoint,
                    handler: self.handler,
                    eventLoop: self.eventLoop,
                    logger: self.logger
                )
            } else {

                try await withThrowingTaskGroup(of: Void.self) { group in

                    self.logger.trace("Starting \(maxConcurrency) Runtime Interface Clients")
                    for i in 0..<maxConcurrency {

                        group.addTask {
                            var logger = self.logger
                            logger[metadataKey: "RIC"] = "\(i)"
                            try await LambdaRuntime.startRuntimeInterfaceClient(
                                endpoint: runtimeEndpoint,
                                handler: self.handler,
                                eventLoop: self.eventLoop,
                                logger: logger
                            )
                        }
                    }
                    // Wait for all tasks to complete and propagate any errors
                    try await group.waitForAll()
                }
            }

        } else {

            self.logger.trace("Starting the local test HTTP server")
            try await LambdaRuntime.startLocalServer(
                handler: self.handler,
                eventLoop: self.eventLoop,
                logger: self.logger
            )
        }
    }
}
#endif
