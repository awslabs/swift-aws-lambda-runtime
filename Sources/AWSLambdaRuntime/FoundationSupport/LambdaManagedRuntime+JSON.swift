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

#if FoundationJSONSupport
import NIOCore

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import class Foundation.JSONDecoder
import class Foundation.JSONEncoder
#endif

import Logging

@available(LambdaSwift 2.0, *)
extension LambdaCodableAdapterSendable {
    /// Initializes an instance given an encoder, decoder, and a handler with a non-`Void` output.
    ///   - Parameters:
    ///   - encoder: The encoder object that will be used to encode the generic `Output` obtained from the `handler`'s `outputWriter` into a `ByteBuffer`. By default, a JSONEncoder is used.
    ///   - decoder: The decoder object that will be used to decode the received `ByteBuffer` event into the generic `Event` type served to the `handler`. By default, a JSONDecoder is used.
    ///   - handler: The handler object.
    public init(
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder(),
        handler: Handler
    )
    where
        Output: Encodable,
        Output == Handler.Output,
        Encoder == LambdaJSONOutputEncoder<Output>,
        Decoder == LambdaJSONEventDecoder
    {
        self.init(
            encoder: LambdaJSONOutputEncoder(encoder),
            decoder: LambdaJSONEventDecoder(decoder),
            handler: handler
        )
    }

    /// Initializes an instance given a decoder, and a handler with a `Void` output.
    ///   - Parameters:
    ///   - decoder: The decoder object that will be used to decode the received `ByteBuffer` event into the generic `Event` type served to the `handler`. By default, a JSONDecoder is used.
    ///   - handler: The handler object.
    public init(
        decoder: JSONDecoder = JSONDecoder(),
        handler: sending Handler
    )
    where
        Output == Void,
        Handler.Output == Void,
        Decoder == LambdaJSONEventDecoder,
        Encoder == VoidEncoder
    {
        self.init(
            decoder: LambdaJSONEventDecoder(decoder),
            handler: handler
        )
    }
}

@available(LambdaSwift 2.0, *)
extension LambdaManagedRuntime {
    /// Initialize an instance with a `LambdaHandler` defined in the form of a closure **with a non-`Void` return type**.
    /// - Parameters:
    ///   - decoder: The decoder object that will be used to decode the incoming `ByteBuffer` event into the generic `Event` type. `JSONDecoder()` used as default.
    ///   - encoder: The encoder object that will be used to encode the generic `Output` into a `ByteBuffer`. `JSONEncoder()` used as default.
    ///   - logger: The logger to use for the runtime. Defaults to a logger with label "LambdaRuntime".
    ///   - body: The handler in the form of a closure.
    public convenience init<Event: Decodable, Output>(
        decoder: JSONDecoder = JSONDecoder(),
        encoder: JSONEncoder = JSONEncoder(),
        logger: Logger = Logger(label: "LambdaManagedRuntime"),
        body: @Sendable @escaping (Event, LambdaContext) async throws -> Output
    )
    where
        Handler == LambdaCodableAdapterSendable<
            LambdaHandlerAdapterSendable<Event, Output, ClosureHandlerSendable<Event, Output>>,
            Event,
            Output,
            LambdaJSONEventDecoder,
            LambdaJSONOutputEncoder<Output>
        >
    {
        let handler = LambdaCodableAdapterSendable(
            encoder: encoder,
            decoder: decoder,
            handler: LambdaHandlerAdapterSendable(handler: ClosureHandlerSendable(body: body))
        )

        self.init(handler: handler, logger: logger)
    }

    /// Initialize an instance with a `LambdaHandler` defined in the form of a closure **with a `Void` return type**.
    /// - Parameter body: The handler in the form of a closure.
    /// - Parameter decoder: The decoder object that will be used to decode the incoming `ByteBuffer` event into the generic `Event` type. `JSONDecoder()` used as default.
    /// - Parameter logger: The logger to use for the runtime. Defaults to a logger with label "LambdaRuntime".
    public convenience init<Event: Decodable>(
        decoder: JSONDecoder = JSONDecoder(),
        logger: Logger = Logger(label: "LambdaRuntime"),
        body: @Sendable @escaping (Event, LambdaContext) async throws -> Void
    )
    where
        Handler == LambdaCodableAdapterSendable<
            LambdaHandlerAdapterSendable<Event, Void, ClosureHandlerSendable<Event, Void>>,
            Event,
            Void,
            LambdaJSONEventDecoder,
            VoidEncoder
        >
    {
        let handler = LambdaCodableAdapterSendable(
            decoder: LambdaJSONEventDecoder(decoder),
            handler: LambdaHandlerAdapterSendable(handler: ClosureHandlerSendable(body: body))
        )

        self.init(handler: handler, logger: logger)
    }

    /// Initialize an instance directly with a `LambdaHandler`, when `Event` is `Decodable` and `Output` is `Void`.
    /// - Parameters:
    ///   - decoder: The decoder object that will be used to decode the incoming `ByteBuffer` event into the generic `Event` type. `JSONDecoder()` used as default.
    ///   - logger: The logger to use for the runtime. Defaults to a logger with label "LambdaRuntime".
    ///   - lambdaHandler: A type that conforms to the `LambdaHandler` and `Sendable` protocols, whose `Event` is `Decodable` and `Output` is `Void`
    public convenience init<Event: Decodable, LHandler: LambdaHandler & Sendable>(
        decoder: JSONDecoder = JSONDecoder(),
        logger: Logger = Logger(label: "LambdaRuntime"),
        lambdaHandler: LHandler
    )
    where
        Handler == LambdaCodableAdapterSendable<
            LambdaHandlerAdapterSendable<Event, Void, LHandler>,
            Event,
            Void,
            LambdaJSONEventDecoder,
            VoidEncoder
        >,
        LHandler.Event == Event,
        LHandler.Output == Void
    {
        let handler = LambdaCodableAdapterSendable(
            decoder: LambdaJSONEventDecoder(decoder),
            handler: LambdaHandlerAdapterSendable(handler: lambdaHandler)
        )

        self.init(handler: handler, logger: logger)
    }

    /// Initialize an instance directly with a `LambdaHandler`, when `Event` is `Decodable` and `Output` is `Encodable`.
    /// - Parameters:
    ///   - decoder: The decoder object that will be used to decode the incoming `ByteBuffer` event into the generic `Event` type. `JSONDecoder()` used as default.
    ///   - encoder: The encoder object that will be used to encode the generic `Output` into a `ByteBuffer`. `JSONEncoder()` used as default.
    ///   - logger: The logger to use for the runtime. Defaults to a logger with label "LambdaRuntime".
    ///   - lambdaHandler: A type that conforms to the `LambdaHandler` and `Sendable` protocols, whose `Event` is `Decodable` and `Output` is `Encodable`
    public convenience init<Event: Decodable, Output, LHandler: LambdaHandler & Sendable>(
        decoder: JSONDecoder = JSONDecoder(),
        encoder: JSONEncoder = JSONEncoder(),
        logger: Logger = Logger(label: "LambdaRuntime"),
        lambdaHandler: LHandler
    )
    where
        Handler == LambdaCodableAdapterSendable<
            LambdaHandlerAdapterSendable<Event, Output, LHandler>,
            Event,
            Output,
            LambdaJSONEventDecoder,
            LambdaJSONOutputEncoder<Output>
        >,
        LHandler.Event == Event,
        LHandler.Output == Output
    {
        let handler = LambdaCodableAdapterSendable(
            encoder: encoder,
            decoder: decoder,
            handler: LambdaHandlerAdapterSendable(handler: lambdaHandler)
        )

        self.init(handler: handler, logger: logger)
    }
}
#endif  // trait: FoundationJSONSupport

#endif  // trait: ManagedRuntimeSupport
