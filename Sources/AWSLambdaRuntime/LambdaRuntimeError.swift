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

@usableFromInline
package struct LambdaRuntimeError: Error {
    @usableFromInline
    package enum Code: Sendable {
        /// internal error codes for LambdaRuntimeClient
        case closingRuntimeClient

        case connectionToControlPlaneLost
        case connectionToControlPlaneGoingAway
        case invocationMissingMetadata

        case writeAfterFinishHasBeenSent
        case finishAfterFinishHasBeenSent
        case unexpectedStatusCodeForRequest

        case nextInvocationMissingHeaderRequestID
        case nextInvocationMissingHeaderDeadline
        case nextInvocationMissingHeaderInvokeFuctionARN

        case missingLambdaRuntimeAPIEnvironmentVariable
        case runtimeCanOnlyBeStartedOnce
        case invalidPort
    }

    @usableFromInline
    package init(code: Code, underlying: (any Error)? = nil) {
        self.code = code
        self.underlying = underlying
    }

    @usableFromInline
    package var code: Code
    @usableFromInline
    package var underlying: (any Error)?

}
