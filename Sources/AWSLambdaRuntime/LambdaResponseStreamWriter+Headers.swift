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

public import NIOCore

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A response structure specifically designed for streaming Lambda responses that contains
/// HTTP status code and headers without body content.
///
/// This structure is used with `LambdaResponseStreamWriter.writeStatusAndHeaders(_:)` to send
/// HTTP response metadata before streaming the response body.
public struct StreamingLambdaStatusAndHeadersResponse: Codable, Sendable {
    /// The HTTP status code for the response (e.g., 200, 404, 500)
    public let statusCode: Int

    /// Dictionary of single-value HTTP headers
    public let headers: [String: String]?

    /// Dictionary of multi-value HTTP headers (e.g., Set-Cookie headers)
    public let multiValueHeaders: [String: [String]]?

    /// Creates a new streaming Lambda response with status code and optional headers
    ///
    /// - Parameters:
    ///   - statusCode: The HTTP status code for the response
    ///   - headers: Optional dictionary of single-value HTTP headers
    ///   - multiValueHeaders: Optional dictionary of multi-value HTTP headers
    public init(
        statusCode: Int,
        headers: [String: String]? = nil,
        multiValueHeaders: [String: [String]]? = nil
    ) {
        self.statusCode = statusCode
        self.headers = headers
        self.multiValueHeaders = multiValueHeaders
    }
}

extension LambdaResponseStreamWriter {
    /// Writes the HTTP status code and headers to the response stream.
    ///
    /// This method serializes the status and headers as JSON and writes them to the stream,
    /// followed by eight null bytes as a separator before the response body.
    ///
    /// - Parameters:
    ///   - response: The status and headers response to write
    ///   - encoder: The encoder to use for serializing the response,
    /// - Throws: An error if JSON serialization or writing fails
    public func writeStatusAndHeaders<Encoder: LambdaOutputEncoder>(
        _ response: StreamingLambdaStatusAndHeadersResponse,
        encoder: Encoder
    ) async throws where Encoder.Output == StreamingLambdaStatusAndHeadersResponse {

        // Convert JSON headers to an array of bytes in a ByteBuffer
        var buffer = ByteBuffer()
        try encoder.encode(response, into: &buffer)

        // Write eight null bytes as separator
        buffer.writeBytes([0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])

        // Write the JSON data and the separator
        try await self.write(buffer, hasCustomHeaders: true)
    }

    /// Write a response part into the stream. Bytes written are streamed continually.
    /// This implementation avoids having to modify all the tests and other part of the code that use this function signature
    /// - Parameter buffer: The buffer to write.
    public func write(_ buffer: ByteBuffer) async throws {
        // Write the buffer to the response stream
        try await self.write(buffer, hasCustomHeaders: false)
    }
}
