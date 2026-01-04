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
import NIOHTTP1

@available(LambdaSwift 2.0, *)
enum ControlPlaneRequest: Hashable {
    case next
    case invocationResponse(String, ByteBuffer?)
    case invocationError(String, ErrorResponse)
    case initializationError(ErrorResponse)
}

@available(LambdaSwift 2.0, *)
enum ControlPlaneResponse: Hashable {
    case next(InvocationMetadata, ByteBuffer)
    case accepted
    case error(ErrorResponse)
}

@usableFromInline
@available(LambdaSwift 2.0, *)
package struct InvocationMetadata: Hashable, Sendable {
    @usableFromInline
    package let requestID: String
    @usableFromInline
    package let deadlineInMillisSinceEpoch: Int64
    @usableFromInline
    package let invokedFunctionARN: String
    @usableFromInline
    package let traceID: String
    @usableFromInline
    package let clientContext: String?
    @usableFromInline
    package let cognitoIdentity: String?
    @usableFromInline
    package let tenantID: String?

    package init(headers: HTTPHeaders) throws(LambdaRuntimeError) {
        guard let requestID = headers.first(name: AmazonHeaders.requestID), !requestID.isEmpty else {
            throw LambdaRuntimeError(code: .nextInvocationMissingHeaderRequestID)
        }

        guard let deadline = headers.first(name: AmazonHeaders.deadline),
            let unixTimeInMilliseconds = Int64(deadline)
        else {
            throw LambdaRuntimeError(code: .nextInvocationMissingHeaderDeadline)
        }

        guard let invokedFunctionARN = headers.first(name: AmazonHeaders.invokedFunctionARN) else {
            throw LambdaRuntimeError(code: .nextInvocationMissingHeaderInvokeFuctionARN)
        }

        self.requestID = requestID
        self.deadlineInMillisSinceEpoch = unixTimeInMilliseconds
        self.invokedFunctionARN = invokedFunctionARN
        self.traceID =
            headers.first(name: AmazonHeaders.traceID) ?? "Root=\(AmazonHeaders.generateXRayTraceID());Sampled=0"
        self.clientContext = headers["Lambda-Runtime-Client-Context"].first
        self.cognitoIdentity = headers["Lambda-Runtime-Cognito-Identity"].first
        self.tenantID = headers[AmazonHeaders.tenantID].first
    }
}

struct ErrorResponse: Hashable, Codable {
    var errorType: String
    var errorMessage: String
}

extension ErrorResponse {
    func toJSONBytes() -> [UInt8] {
        var bytes = [UInt8]()
        bytes.append(UInt8(ascii: "{"))
        bytes.append(contentsOf: #""errorType":"#.utf8)
        self.errorType.encodeAsJSONString(into: &bytes)
        bytes.append(contentsOf: #","errorMessage":"#.utf8)
        self.errorMessage.encodeAsJSONString(into: &bytes)
        bytes.append(UInt8(ascii: "}"))
        return bytes
    }
}
