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

import Testing

@testable import AWSLambdaPluginHelper

@Suite("Deployer IAM role propagation detection")
struct DeployerIAMRoleTests {

    @available(LambdaSwift 2.0, *)
    @Test("InvalidParameterValueException about an unassumable role is retryable")
    func roleNotYetAssumableIsRetryable() {
        let deployer = Deployer()
        #expect(
            deployer.isRoleNotYetAssumable(
                errorCode: "InvalidParameterValueException",
                message: "The role defined for the function cannot be assumed by Lambda."
            )
        )
    }

    @available(LambdaSwift 2.0, *)
    @Test("A different InvalidParameterValueException is not retried")
    func unrelatedInvalidParameterIsNotRetryable() {
        let deployer = Deployer()
        #expect(
            !deployer.isRoleNotYetAssumable(
                errorCode: "InvalidParameterValueException",
                message: "1 validation error detected: value at 'memorySize' failed to satisfy constraint."
            )
        )
    }

    @available(LambdaSwift 2.0, *)
    @Test("A matching message under a different error code is not retried")
    func differentErrorCodeIsNotRetryable() {
        let deployer = Deployer()
        #expect(
            !deployer.isRoleNotYetAssumable(
                errorCode: "ResourceConflictException",
                message: "The role defined for the function cannot be assumed by Lambda."
            )
        )
    }

    @available(LambdaSwift 2.0, *)
    @Test("A nil message is not retried")
    func missingMessageIsNotRetryable() {
        let deployer = Deployer()
        #expect(
            !deployer.isRoleNotYetAssumable(
                errorCode: "InvalidParameterValueException",
                message: nil
            )
        )
    }
}
