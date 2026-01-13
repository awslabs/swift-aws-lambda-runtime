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

import NIOCore

/// Adapts a ``LambdaHandler`` conforming handler to conform to ``LambdaWithBackgroundProcessingHandler``.
@available(LambdaSwift 2.0, *)
public struct LambdaHandlerAdapterSendable<
    Event: Decodable,
    Output,
    Handler: LambdaHandler & Sendable
>: Sendable, LambdaWithBackgroundProcessingHandler where Handler.Event == Event, Handler.Output == Output {
    @usableFromInline let handler: Handler

    /// Initializes an instance given a concrete handler.
    /// - Parameter handler: The ``LambdaHandler`` conforming handler that is to be adapted to ``LambdaWithBackgroundProcessingHandler``.
    @inlinable
    public init(handler: sending Handler) {
        self.handler = handler
    }

    /// Passes the generic `Event` object to the ``LambdaHandler/handle(_:context:)`` function, and
    /// the resulting output is then written to ``LambdaWithBackgroundProcessingHandler``'s `outputWriter`.
    /// - Parameters:
    ///   - event: The received event.
    ///   - outputWriter: The writer to write the computed response to.
    ///   - context: The ``LambdaContext`` containing the invocation's metadata.
    @inlinable
    public func handle(
        _ event: Event,
        outputWriter: some LambdaResponseWriter<Output>,
        context: LambdaContext
    ) async throws {
        let output = try await self.handler.handle(event, context: context)
        try await outputWriter.write(output)
    }
}

/// Adapts a ``LambdaWithBackgroundProcessingHandler`` conforming handler to conform to ``StreamingLambdaHandler``.
@available(LambdaSwift 2.0, *)
public struct LambdaCodableAdapterSendable<
    Handler: LambdaWithBackgroundProcessingHandler & Sendable,
    Event: Decodable,
    Output,
    Decoder: LambdaEventDecoder & Sendable,
    Encoder: LambdaOutputEncoder & Sendable
>: Sendable, StreamingLambdaHandler where Handler.Event == Event, Handler.Output == Output, Encoder.Output == Output {
    @usableFromInline let handler: Handler
    @usableFromInline let encoder: Encoder
    @usableFromInline let decoder: Decoder
    @usableFromInline var byteBuffer: ByteBuffer = .init()

    /// Initializes an instance given an encoder, decoder, and a handler with a non-`Void` output.
    /// - Parameters:
    ///   - encoder: The encoder object that will be used to encode the generic `Output` obtained from the `handler`'s `outputWriter` into a `ByteBuffer`.
    ///   - decoder: The decoder object that will be used to decode the received `ByteBuffer` event into the generic `Event` type served to the `handler`.
    ///   - handler: The handler object.
    @inlinable
    public init(encoder: Encoder, decoder: Decoder, handler: Handler) where Output: Encodable {
        self.encoder = encoder
        self.decoder = decoder
        self.handler = handler
    }

    /// Initializes an instance given a decoder, and a handler with a `Void` output.
    ///   - Parameters:
    ///     - decoder: The decoder object that will be used to decode the received `ByteBuffer` event into the generic `Event` type served to the `handler`.
    ///     - handler: The handler object.
    @inlinable
    public init(decoder: Decoder, handler: Handler) where Output == Void, Encoder == VoidEncoder {
        self.encoder = VoidEncoder()
        self.decoder = decoder
        self.handler = handler
    }

    /// A ``StreamingLambdaHandler/handle(_:responseWriter:context:)`` wrapper.
    /// - Parameters:
    ///   - request: The received event.
    ///   - responseWriter: The writer to write the computed response to.
    ///   - context: The ``LambdaContext`` containing the invocation's metadata.
    @inlinable
    public mutating func handle<Writer: LambdaResponseStreamWriter & Sendable>(
        _ request: ByteBuffer,
        responseWriter: Writer,
        context: LambdaContext
    ) async throws {
        let event = try self.decoder.decode(Event.self, from: request)

        let writer = LambdaCodableResponseWriter<Output, Encoder, Writer>(
            encoder: self.encoder,
            streamWriter: responseWriter
        )
        try await self.handler.handle(event, outputWriter: writer, context: context)
    }
}

#endif
