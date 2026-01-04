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

#if ServiceLifecycleSupport
import ServiceLifecycle

@available(LambdaSwift 2.0, *)
extension LambdaRuntime: Service {
    public func run() async throws {
        try await cancelWhenGracefulShutdown {
            try await self._run()
        }
    }
}
#endif
