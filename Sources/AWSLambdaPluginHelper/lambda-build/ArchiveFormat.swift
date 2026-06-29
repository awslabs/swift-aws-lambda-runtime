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

/// The packaging format requested via `--archive-format`.
///
/// This enum is purely the parsed user choice. The packaging flow lives in the ``ArchiveBackend``
/// types, and backend construction lives on ``BuilderConfiguration/makeArchiveBackend()``.
@available(LambdaSwift 2.0, *)
enum ArchiveFormat: String, CustomStringConvertible {
    /// A ZIP package suitable for upload to AWS Lambda.
    case zip
    /// An OCI image. Not yet supported.
    case oci

    var isSupported: Bool {
        switch self {
        case .zip: return true
        case .oci: return false
        }
    }

    static func parse(_ value: String?) throws -> Self {
        guard let value else {
            return .zip
        }

        guard let format = ArchiveFormat(rawValue: value.lowercased()) else {
            throw BuilderErrors.invalidArgument(
                "invalid archive format '\(value)'. Use 'zip' or 'oci'."
            )
        }

        guard format.isSupported else {
            throw BuilderErrors.unsupportedArchiveFormat(format)
        }

        return format
    }

    var description: String {
        self.rawValue
    }
}
