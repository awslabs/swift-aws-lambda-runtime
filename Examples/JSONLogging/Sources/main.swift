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

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

// This example demonstrates structured JSON logging in AWS Lambda
// When AWS_LAMBDA_LOG_FORMAT=JSON, logs are automatically formatted as JSON

struct Request: Decodable {
    let name: String
    let level: String?
}

struct Response: Encodable {
    let message: String
    let timestamp: String
}

// A plain function with no `LambdaContext` or `Logger` parameter. It reads the task-local
// `Logger.current`, which the runtime binds to the per-invocation logger for the duration
// of the handler call. As a result, the request ID and trace ID metadata are included
// automatically — without threading a logger through the call stack.
// Note: requires Swift 6.2+ for the runtime to bind `Logger.current`; on older toolchains
// this logs through the process-wide default logger instead.
func validate(_ event: Request) {
    Logger.current.debug("Validating request", metadata: ["name": .string(event.name)])
    if event.name.isEmpty {
        Logger.current.warning("Received a request with an empty name")
    }
}

let runtime = LambdaRuntime {
    (event: Request, context: LambdaContext) in

    // These log statements will be formatted as JSON when AWS_LAMBDA_LOG_FORMAT=JSON
    context.logger.trace("Processing request with trace level")
    context.logger.debug("Request details", metadata: ["name": .string(event.name)])
    context.logger.info("Processing request for \(event.name)")

    // `validate` takes no logger — it reads `Logger.current`, yet its log lines still carry
    // this invocation's request ID and trace ID because the runtime bound the per-invocation
    // logger as the task-local before calling the handler.
    validate(event)

    if let level = event.level {
        context.logger.notice("Custom log level requested: \(level)")
    }

    context.logger.warning("This is a warning message")

    // Simulate different scenarios
    if event.name.lowercased() == "error" {
        context.logger.error(
            "Error scenario triggered",
            metadata: [
                "errorType": .string("SimulatedError"),
                "errorCode": .string("TEST_ERROR"),
            ]
        )
    }

    return Response(
        message: "Hello \(event.name)! Logs are in JSON format.",
        timestamp: Date().ISO8601Format()
    )
}

try await runtime.run()
