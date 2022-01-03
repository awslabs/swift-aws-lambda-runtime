//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftAWSLambdaRuntime open source project
//
// Copyright (c) 2017-2018 Apple Inc. and the SwiftAWSLambdaRuntime project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftAWSLambdaRuntime project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

#if os(Linux)
import Glibc
#else
import Darwin.C
#endif

import Backtrace
import Logging
import NIOCore
import NIOPosix

public enum Lambda {
    /// Utility to access/read environment variables
    public static func env(_ name: String) -> String? {
        guard let value = getenv(name) else {
            return nil
        }
        return String(cString: value)
    }

    /// Run a Lambda defined by implementing the ``ByteBufferLambdaHandler`` protocol.
    /// The Runtime will manage the Lambdas application lifecycle automatically. It will invoke the
    /// ``ByteBufferLambdaHandler/factory(context:)`` to create a new Handler.
    ///
    /// - parameters:
    ///     - factory: A `ByteBufferLambdaHandler` factory.
    ///
    /// - note: This is a blocking operation that will run forever, as its lifecycle is managed by the AWS Lambda Runtime Engine.
    internal static func run<Handler: ByteBufferLambdaHandler>(configuration: Configuration = .init(), handlerType: Handler.Type) -> Result<Int, Error> {
        let _run = { (configuration: Configuration) -> Result<Int, Error> in
            Backtrace.install()
            var logger = Logger(label: "Lambda")
            logger.logLevel = configuration.general.logLevel

            var result: Result<Int, Error>!
            MultiThreadedEventLoopGroup.withCurrentThreadAsEventLoop { eventLoop in
                let runtime = LambdaRuntime<Handler>(eventLoop: eventLoop, logger: logger, configuration: configuration)
                #if DEBUG
                let signalSource = trap(signal: configuration.lifecycle.stopSignal) { signal in
                    logger.info("intercepted signal: \(signal)")
                    runtime.shutdown()
                }
                #endif

                runtime.start().flatMap {
                    runtime.shutdownFuture
                }.whenComplete { lifecycleResult in
                    #if DEBUG
                    signalSource.cancel()
                    #endif
                    eventLoop.shutdownGracefully { error in
                        if let error = error {
                            preconditionFailure("Failed to shutdown eventloop: \(error)")
                        }
                    }
                    result = lifecycleResult
                }
            }

            logger.info("shutdown completed")
            return result
        }

        // start local server for debugging in DEBUG mode only
        #if DEBUG
        if Lambda.env("LOCAL_LAMBDA_SERVER_ENABLED").flatMap(Bool.init) ?? false {
            do {
                return try Lambda.withLocalServer {
                    _run(configuration)
                }
            } catch {
                return .failure(error)
            }
        } else {
            return _run(configuration)
        }
        #else
        return _run(configuration, factory)
        #endif
    }
}
