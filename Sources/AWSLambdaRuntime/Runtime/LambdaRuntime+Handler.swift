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

@available(LambdaSwift 2.0, *)
extension LambdaRuntime {
    /// Initialize an instance with a ``StreamingLambdaHandler`` in the form of a closure.
    /// - Parameter
    ///   - logger: The logger to use for the runtime. Defaults to a logger with label "LambdaRuntime".
    ///   - body: The handler in the form of a closure.
    public convenience init(
        logger: Logger = Logger(label: "LambdaRuntime"),
        body: @Sendable @escaping (ByteBuffer, LambdaResponseStreamWriter, LambdaContext) async throws -> Void

    ) where Handler == StreamingClosureHandler {
        self.init(handler: StreamingClosureHandler(body: body), logger: logger)
    }

    /// Initialize an instance with a ``LambdaHandler`` defined in the form of a closure **with a non-`Void` return type**, an encoder, and a decoder.
    /// - Parameters:
    ///   - encoder: The encoder object that will be used to encode the generic `Output` into a `ByteBuffer`.
    ///   - decoder: The decoder object that will be used to decode the incoming `ByteBuffer` event into the generic `Event` type.
    ///   - logger: The logger to use for the runtime. Defaults to a logger with label "LambdaRuntime".
    ///   - body: The handler in the form of a closure.
    public convenience init<
        Event: Decodable,
        Output: Encodable,
        Encoder: LambdaOutputEncoder,
        Decoder: LambdaEventDecoder
    >(
        encoder: sending Encoder,
        decoder: sending Decoder,
        logger: Logger = Logger(label: "LambdaRuntime"),
        body: sending @escaping (Event, LambdaContext) async throws -> Output
    )
    where
        Handler == LambdaCodableAdapter<
            LambdaHandlerAdapter<Event, Output, ClosureHandler<Event, Output>>,
            Event,
            Output,
            Decoder,
            Encoder
        >
    {
        let closureHandler = ClosureHandler(body: body)
        let streamingAdapter = LambdaHandlerAdapter(handler: closureHandler)
        let codableWrapper = LambdaCodableAdapter(
            encoder: encoder,
            decoder: decoder,
            handler: streamingAdapter
        )

        self.init(handler: codableWrapper, logger: logger)
    }

    /// Initialize an instance with a ``LambdaHandler`` defined in the form of a closure **with a `Void` return type**, an encoder, and a decoder.
    /// - Parameters:
    ///   - decoder: The decoder object that will be used to decode the incoming `ByteBuffer` event into the generic `Event` type.
    ///   - logger: The logger to use for the runtime. Defaults to a logger with label "LambdaRuntime".
    ///   - body: The handler in the form of a closure.
    public convenience init<Event: Decodable, Decoder: LambdaEventDecoder>(
        decoder: sending Decoder,
        logger: Logger = Logger(label: "LambdaRuntime"),
        body: sending @escaping (Event, LambdaContext) async throws -> Void
    )
    where
        Handler == LambdaCodableAdapter<
            LambdaHandlerAdapter<Event, Void, ClosureHandler<Event, Void>>,
            Event,
            Void,
            Decoder,
            VoidEncoder
        >
    {
        let handler = LambdaCodableAdapter(
            decoder: decoder,
            handler: LambdaHandlerAdapter(handler: ClosureHandler(body: body))
        )

        self.init(handler: handler, logger: logger)
    }
}
