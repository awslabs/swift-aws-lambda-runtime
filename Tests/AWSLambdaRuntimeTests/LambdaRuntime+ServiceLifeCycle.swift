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
@testable import AWSLambdaRuntime
import ServiceLifecycle
import Testing
import Logging
import UnixSignals

extension LambdaRuntimeTests {
    @Test
    @available(LambdaSwift 2.0, *)
    func testLambdaRuntimeGracefulShutdown() async throws {
        let runtime = LambdaRuntime {
            (event: String, context: LambdaContext) in
            "Hello \(event)"
        }

        let serviceGroup = ServiceGroup(
            services: [runtime],
            gracefulShutdownSignals: [.sigterm, .sigint],
            logger: Logger(label: "TestLambdaRuntimeGracefulShutdown")
        )
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await serviceGroup.run()
            }
            // wait a small amount to ensure we are waiting for continuation
            try await Task.sleep(for: .milliseconds(100))

            await serviceGroup.triggerGracefulShutdown()
        }
    }
}
#endif
