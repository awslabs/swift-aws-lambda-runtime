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
import Synchronization

// This is our guardian to ensure only one LambdaRuntime is running at the time
// We use an Atomic here to ensure thread safety
@available(LambdaSwift 2.0, *)
private let _isRunning = Atomic<Bool>(false)

@available(LambdaSwift 2.0, *)
public final class LambdaRuntime<Handler>: Sendable where Handler: StreamingLambdaHandler {
    @usableFromInline
    /// we protect the handler behind a Mutex to ensure that we only ever have one copy of it
    let handlerStorage: SendingStorage<Handler>
    @usableFromInline
    let logger: Logger
    @usableFromInline
    let eventLoop: EventLoop

    public init(
        handler: sending Handler,
        eventLoop: EventLoop = Lambda.defaultEventLoop,
        logger: Logger = Logger(label: "LambdaRuntime")
    ) {
        self.handlerStorage = SendingStorage(handler)
        self.eventLoop = eventLoop

        // by setting the log level here, we understand it can not be changed dynamically at runtime
        // developers have to wait for AWS Lambda to dispose and recreate a runtime environment to pickup a change
        // this approach is less flexible but more performant than reading the value of the environment variable at each invocation
        var log = logger

        // use the LOG_LEVEL environment variable to set the log level.
        // if the environment variable is not set, use the default log level from the logger provided
        log.logLevel = Lambda.env("LOG_LEVEL").flatMap { Logger.Level(rawValue: $0) } ?? logger.logLevel

        self.logger = log
        self.logger.debug("LambdaRuntime initialized")
    }

    #if !ServiceLifecycleSupport
    public func run() async throws {
        try await _run()
    }
    #endif

    /// Make sure only one run() is called at a time
    internal func _run() async throws {

        // we use an atomic global variable to ensure only one LambdaRuntime is running at the time
        let (_, original) = _isRunning.compareExchange(expected: false, desired: true, ordering: .acquiringAndReleasing)

        // if the original value was already true, run() is already running
        if original {
            throw LambdaRuntimeError(code: .runtimeCanOnlyBeStartedOnce)
        }

        defer {
            _isRunning.store(false, ordering: .releasing)
        }

        // The handler can be non-sendable, we want to ensure we only ever have one copy of it
        let handler = try? self.handlerStorage.get()
        guard let handler else {
            throw LambdaRuntimeError(code: .handlerCanOnlyBeGetOnce)
        }

        // are we running inside an AWS Lambda runtime environment ?
        // AWS_LAMBDA_RUNTIME_API is set when running on Lambda
        // https://docs.aws.amazon.com/lambda/latest/dg/runtimes-api.html
        if let runtimeEndpoint = Lambda.env("AWS_LAMBDA_RUNTIME_API") {

            let ipAndPort = runtimeEndpoint.split(separator: ":", maxSplits: 1)
            let ip = String(ipAndPort[0])
            guard let port = Int(ipAndPort[1]) else { throw LambdaRuntimeError(code: .invalidPort) }

            do {
                try await LambdaRuntimeClient.withRuntimeClient(
                    configuration: .init(ip: ip, port: port),
                    eventLoop: self.eventLoop,
                    logger: self.logger
                ) { runtimeClient in
                    try await Lambda.runLoop(
                        runtimeClient: runtimeClient,
                        handler: handler,
                        logger: self.logger
                    )
                }
            } catch {
                // catch top level errors that have not been handled until now
                // this avoids the runtime to crash and generate a backtrace
                if let error = error as? LambdaRuntimeError,
                    error.code != .connectionToControlPlaneLost
                {
                    // if the error is a LambdaRuntimeError but not a connection error,
                    // we rethrow it to preserve existing behaviour
                    self.logger.error("LambdaRuntime.run() failed with error", metadata: ["error": "\(error)"])
                    throw error
                } else {
                    self.logger.trace("LambdaRuntime.run() connection lost")
                }
            }

        } else {

            #if LocalServerSupport

            // we're not running on Lambda and we're compiled in DEBUG mode,
            // let's start a local server for testing

            let host = Lambda.env("LOCAL_LAMBDA_HOST") ?? "127.0.0.1"
            let port = Lambda.env("LOCAL_LAMBDA_PORT").flatMap(Int.init) ?? 7000
            let endpoint = Lambda.env("LOCAL_LAMBDA_INVOCATION_ENDPOINT")

            try await Lambda.withLocalServer(
                host: host,
                port: port,
                invocationEndpoint: endpoint,
                logger: self.logger
            ) {

                try await LambdaRuntimeClient.withRuntimeClient(
                    configuration: .init(ip: host, port: port),
                    eventLoop: self.eventLoop,
                    logger: self.logger
                ) { runtimeClient in
                    try await Lambda.runLoop(
                        runtimeClient: runtimeClient,
                        handler: handler,
                        logger: self.logger
                    )
                }
            }
            #else
            // When the LocalServerSupport trait is disabled, we can't start a local server because the local server code is not compiled.
            throw LambdaRuntimeError(code: .missingLambdaRuntimeAPIEnvironmentVariable)
            #endif
        }
    }
}
