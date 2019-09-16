//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftAwsLambda open source project
//
// Copyright (c) 2017-2018 Apple Inc. and the SwiftAwsLambda project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftAwsLambda project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Logging
import NIO
@testable import SwiftAwsLambda
import XCTest

func runLambda(behavior: LambdaServerBehavior, handler: LambdaHandler) throws {
    let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    let logger = Logger(label: "TestLogger")
    let runner = LambdaRunner(eventLoop: eventLoopGroup.next(), lambdaHandler: handler, lifecycleId: "test")
    let server = try MockLambdaServer(behavior: behavior).start().wait()
    defer {
        // deferd in case initialize/run throw
        XCTAssertNoThrow(try server.stop().wait())
        XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully())
    }
    try runner.initialize(logger: logger).flatMap {
        runner.run(logger: logger)
    }.wait()
}

class EchoHandler: LambdaHandler {
    var initializeCalls = 0

    func initialize(callback: @escaping LambdaInitCallBack) {
        self.initializeCalls += 1
        callback(.success(()))
    }

    func handle(context: LambdaContext, payload: [UInt8], callback: @escaping LambdaCallback) {
        callback(.success(payload))
    }
}

class FailedHandler: LambdaHandler {
    private let reason: String

    public init(_ reason: String) {
        self.reason = reason
    }

    func handle(context: LambdaContext, payload: [UInt8], callback: @escaping LambdaCallback) {
        callback(.failure(Error(description: self.reason)))
    }

    struct Error: Swift.Error, Equatable, CustomStringConvertible {
        let description: String
    }
}

class FailedInitializerHandler: LambdaHandler {
    private let reason: String

    public init(_ reason: String) {
        self.reason = reason
    }

    func handle(context: LambdaContext, payload: [UInt8], callback: @escaping LambdaCallback) {
        callback(.success(payload))
    }

    func initialize(callback: @escaping LambdaInitCallBack) {
        callback(.failure(Error(description: self.reason)))
    }

    public struct Error: Swift.Error, Equatable, CustomStringConvertible {
        let description: String
    }
}
