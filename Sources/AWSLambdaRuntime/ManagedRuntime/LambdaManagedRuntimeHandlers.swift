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

#if ManagedRuntimeSupport

/// A ``LambdaHandler`` conforming handler object that can be constructed with a closure.
/// Allows for a handler to be defined in a clean manner, leveraging Swift's trailing closure syntax.
@available(LambdaSwift 2.0, *)
public struct ClosureHandlerSendable<Event: Decodable, Output>: LambdaHandler, Sendable {
    let body: @Sendable (Event, LambdaContext) async throws -> Output

    /// Initialize with a closure handler over generic `Input` and `Output` types.
    /// - Parameter body: The handler function written as a closure.
    public init(body: @Sendable @escaping (Event, LambdaContext) async throws -> Output) where Output: Encodable {
        self.body = body
    }

    /// Initialize with a closure handler over a generic `Input` type, and a `Void` `Output`.
    /// - Parameter body: The handler function written as a closure.
    public init(body: @Sendable @escaping (Event, LambdaContext) async throws -> Void) where Output == Void {
        self.body = body
    }

    /// Calls the provided `self.body` closure with the generic `Event` object representing the incoming event, and the ``LambdaContext``
    /// - Parameters:
    ///   - event: The generic `Event` object representing the invocation's input data.
    ///   - context: The ``LambdaContext`` containing the invocation's metadata.
    public func handle(_ event: Event, context: LambdaContext) async throws -> Output {
        try await self.body(event, context)
    }
}
#endif
