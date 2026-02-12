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

@testable import AWSLambdaRuntime

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension Date {
    var millisSinceEpoch: Int64 {
        Int64(self.timeIntervalSince1970 * 1000)
    }
}
// MARK: - Test Helpers

@available(LambdaSwift 2.0, *)
extension LambdaContext {
    public static func makeTest() -> LambdaContext {
        LambdaContext.__forTestsOnly(
            requestID: "test-request-id",
            traceID: "test-trace-id",
            tenantID: "test-tenant-id",
            invokedFunctionARN: "arn:aws:lambda:us-east-1:123456789012:function:test",
            timeout: .seconds(30),
            logger: Logger(label: "MockedLambdaContext")
        )
    }
}
