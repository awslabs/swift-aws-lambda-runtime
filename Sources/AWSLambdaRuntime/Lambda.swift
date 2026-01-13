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

import Dispatch
import Logging
import NIOCore
import NIOPosix

#if os(macOS)
import Darwin.C
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif os(Windows)
import ucrt
#else
#error("Unsupported platform")
#endif

@available(LambdaSwift 2.0, *)
public enum Lambda {
    @inlinable
    package static func runLoop<RuntimeClient: LambdaRuntimeClientProtocol, Handler>(
        runtimeClient: RuntimeClient,
        handler: Handler,
        logger: Logger
    ) async throws where Handler: StreamingLambdaHandler {
        var handler = handler

        var logger = logger
        do {
            while !Task.isCancelled {

                logger.trace("Waiting for next invocation")
                let (invocation, writer) = try await runtimeClient.nextInvocation()
                logger[metadataKey: "aws-request-id"] = "\(invocation.metadata.requestID)"

                // when log level is trace or lower, print the first 6 Mb of the payload
                let bytes = invocation.event
                let maxPayloadPreviewSize = 6 * 1024 * 1024
                var metadata: Logger.Metadata? = nil
                if logger.logLevel <= .trace,
                    let buffer = bytes.getSlice(at: 0, length: min(bytes.readableBytes, maxPayloadPreviewSize))
                {
                    metadata = [
                        "Event's first bytes": .string(
                            String(buffer: buffer) + (bytes.readableBytes > maxPayloadPreviewSize ? "..." : "")
                        )
                    ]
                }
                logger.trace(
                    "Sending invocation event to lambda handler",
                    metadata: metadata
                )

                do {
                    try await handler.handle(
                        invocation.event,
                        responseWriter: writer,
                        context: LambdaContext(
                            requestID: invocation.metadata.requestID,
                            traceID: invocation.metadata.traceID,
                            tenantID: invocation.metadata.tenantID,
                            invokedFunctionARN: invocation.metadata.invokedFunctionARN,
                            deadline: LambdaClock.Instant(
                                millisecondsSinceEpoch: invocation.metadata.deadlineInMillisSinceEpoch
                            ),
                            logger: logger
                        )
                    )
                    logger.trace("Handler finished processing invocation")
                } catch {
                    logger.trace("Handler failed processing invocation", metadata: ["Handler error": "\(error)"])
                    try await writer.reportError(error)
                    continue
                }
                logger.handler.metadata.removeValue(forKey: "aws-request-id")
            }
        } catch is CancellationError {
            // don't allow cancellation error to propagate further
        }

    }

    /// The default EventLoop the Lambda is scheduled on.
    public static let defaultEventLoop: any EventLoop = NIOSingletons.posixEventLoopGroup.next()
}

// MARK: - Public API

@available(LambdaSwift 2.0, *)
extension Lambda {
    /// Utility to access/read environment variables
    public static func env(_ name: String) -> String? {
        guard let value = getenv(name) else {
            return nil
        }
        return String(cString: value)
    }
}
