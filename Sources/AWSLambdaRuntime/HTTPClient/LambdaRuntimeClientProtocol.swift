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

import NIOCore

@usableFromInline
package protocol LambdaRuntimeClientResponseStreamWriter: LambdaResponseStreamWriter {
    func write(_ buffer: ByteBuffer, hasCustomHeaders: Bool) async throws
    func finish() async throws
    func writeAndFinish(_ buffer: ByteBuffer) async throws
    func reportError(_ error: any Error) async throws
}

@usableFromInline
@available(LambdaSwift 2.0, *)
package protocol LambdaRuntimeClientProtocol {
    associatedtype Writer: LambdaRuntimeClientResponseStreamWriter

    func nextInvocation() async throws -> (Invocation, Writer)
}

@usableFromInline
@available(LambdaSwift 2.0, *)
package struct Invocation: Sendable {
    @usableFromInline
    package var metadata: InvocationMetadata
    @usableFromInline
    package var event: ByteBuffer

    package init(metadata: InvocationMetadata, event: ByteBuffer) {
        self.metadata = metadata
        self.event = event
    }
}
