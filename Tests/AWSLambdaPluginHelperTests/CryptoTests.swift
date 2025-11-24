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
import Testing

@testable import AWSLambdaPluginHelper

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@Suite
struct CryptoTests {

    @Test
    func testSHA256() {

        // given
        let input = "hello world"
        let expected = "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9"

        // when
        let result = Digest.sha256(input.array).toHexString()

        // then
        #expect(result == expected)
    }

    @Test
    func testHMAC() throws {

        // given
        let input = "hello world"
        let secret = "secretkey"
        let expected = "ae6cd2605d622316564d1f76bfc0c04f89d9fafb14f45b3e18c2a3e28bdef29d"

        // when
        let authenticator = HMAC(key: secret.array, variant: .sha2(.sha256))

        #expect(throws: Never.self) {
            let result = try authenticator.authenticate(input.array).toHexString()
            // then
            #expect(result == expected)
        }

    }

    @Test
    func testHMACExtension() throws {

        // given
        let input = "hello world"
        let secret = "secretkey"
        let expected = "ae6cd2605d622316564d1f76bfc0c04f89d9fafb14f45b3e18c2a3e28bdef29d"

        // when
        let result = try HMAC.authenticate(for: input.array, using: secret.array).toHexString()

        // then
        #expect(result == expected)

    }

}
