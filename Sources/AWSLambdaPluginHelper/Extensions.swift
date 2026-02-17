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

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

// extension Array where Element == UInt8 {
//     public var base64: String {
//         Data(self).base64EncodedString()
//     }
// }

extension Data {
    var bytes: [UInt8] {
        [UInt8](self)
    }
}

extension String {
    public var array: [UInt8] {
        Array(self.utf8)
    }
}

extension HMAC {
    public static func authenticate(
        for data: [UInt8],
        using key: [UInt8],
        variant: HMAC.Variant = .sha2(.sha256)
    ) throws -> [UInt8] {
        let authenticator = HMAC(key: key, variant: variant)
        return try authenticator.authenticate(data)
    }
    public static func authenticate(
        for data: Data,
        using key: [UInt8],
        variant: HMAC.Variant = .sha2(.sha256)
    ) throws -> [UInt8] {
        let authenticator = HMAC(key: key, variant: variant)
        return try authenticator.authenticate(data.bytes)
    }
}
