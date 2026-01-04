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

public struct LambdaJSONEventDecoder: LambdaEventDecoder {
    @usableFromInline let jsonDecoder: JSONDecoder

    @inlinable
    public init(_ jsonDecoder: JSONDecoder) {
        self.jsonDecoder = jsonDecoder
    }

    @inlinable
    public func decode<Event>(_ type: Event.Type, from buffer: NIOCore.ByteBuffer) throws -> Event
    where Event: Decodable {
        try buffer.getJSONDecodable(
            Event.self,
            decoder: self.jsonDecoder,
            at: buffer.readerIndex,
            length: buffer.readableBytes
        )!  // must work, enough readable bytes
    }
}

public struct LambdaJSONOutputEncoder<Output: Encodable>: LambdaOutputEncoder {
    @usableFromInline let jsonEncoder: JSONEncoder

    @inlinable
    public init(_ jsonEncoder: JSONEncoder) {
        self.jsonEncoder = jsonEncoder
    }

    @inlinable
    public func encode(_ value: Output, into buffer: inout ByteBuffer) throws {
        try buffer.writeJSONEncodable(value, encoder: self.jsonEncoder)
    }
}

@available(LambdaSwift 2.0, *)
extension LambdaCodableAdapter {
    /// Initializes an instance given an encoder, decoder, and a handler with a non-`Void` output.
    ///   - Parameters:
    ///   - encoder: The encoder object that will be used to encode the generic `Output` obtained from the `handler`'s `outputWriter` into a `ByteBuffer`. By default, a JSONEncoder is used.
    ///   - decoder: The decoder object that will be used to decode the received `ByteBuffer` event into the generic `Event` type served to the `handler`. By default, a JSONDecoder is used.
    ///   - handler: The handler object.
    public init(
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder(),
        handler: sending Handler
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
extension LambdaResponseStreamWriter {
    /// Writes the HTTP status code and headers to the response stream.
    ///
    /// This method serializes the status and headers as JSON and writes them to the stream,
    /// followed by eight null bytes as a separator before the response body.
    ///
    /// - Parameters:
    ///   - response: The status and headers response to write
    ///   - encoder: The encoder to use for serializing the response, use JSONEncoder by default
    /// - Throws: An error if JSON serialization or writing fails
    public func writeStatusAndHeaders(
        _ response: StreamingLambdaStatusAndHeadersResponse,
        encoder: JSONEncoder = JSONEncoder()
    ) async throws {
        encoder.outputFormatting = .withoutEscapingSlashes
        try await self.writeStatusAndHeaders(response, encoder: LambdaJSONOutputEncoder(encoder))
    }
}
#endif  // trait: FoundationJSONSupport
