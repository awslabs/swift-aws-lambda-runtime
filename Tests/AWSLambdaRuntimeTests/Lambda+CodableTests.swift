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
import NIOCore
import Testing

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@Suite
struct JSONTests {

    let logger = Logger(label: "JSONTests")

    struct Foo: Codable {
        var bar: String
    }

    @Test
    func testEncodingConformance() {
        let encoder = LambdaJSONOutputEncoder<Foo>(JSONEncoder())
        let foo = Foo(bar: "baz")
        var byteBuffer = ByteBuffer()

        #expect(throws: Never.self) {
            try encoder.encode(foo, into: &byteBuffer)
        }

        #expect(byteBuffer == ByteBuffer(string: #"{"bar":"baz"}"#))
    }

    @Test
    @available(LambdaSwift 2.0, *)
    func testJSONHandlerWithOutput() async {
        let jsonEncoder = JSONEncoder()
        let jsonDecoder = JSONDecoder()

        let closureHandler = ClosureHandler { (foo: Foo, context) in
            foo
        }

        var handler = LambdaCodableAdapter(
            encoder: jsonEncoder,
            decoder: jsonDecoder,
            handler: LambdaHandlerAdapter(handler: closureHandler)
        )

        let event = ByteBuffer(string: #"{"bar":"baz"}"#)
        let writer = MockLambdaWriter()
        let context = LambdaContext.__forTestsOnly(
            requestID: UUID().uuidString,
            traceID: UUID().uuidString,
            tenantID: nil,
            invokedFunctionARN: "arn:",
            timeout: .milliseconds(6000),
            logger: self.logger
        )

        await #expect(throws: Never.self) {
            try await handler.handle(event, responseWriter: writer, context: context)
        }

        let result = await writer.output
        #expect(result == ByteBuffer(string: #"{"bar":"baz"}"#))
    }

    final actor MockLambdaWriter: LambdaResponseStreamWriter {
        private var _buffer: ByteBuffer?

        var output: ByteBuffer? {
            self._buffer
        }

        func writeAndFinish(_ buffer: ByteBuffer) async throws {
            self._buffer = buffer
        }

        func write(_ buffer: ByteBuffer, hasCustomHeaders: Bool = false) async throws {
            fatalError("Unexpected call")
        }

        func finish() async throws {
            fatalError("Unexpected call")
        }
    }
}
