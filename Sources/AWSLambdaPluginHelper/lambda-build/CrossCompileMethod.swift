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

/// The cross-compilation method requested via `--cross-compile`.
///
/// This enum is purely the parsed user choice. It holds no execution logic: container argument
/// spelling lives in the ``ContainerCLI`` types, the build flow lives in the ``BuildBackend``
/// types, and backend construction lives on ``BuilderConfiguration`` (which holds everything a
/// backend needs).
@available(LambdaSwift 2.0, *)
enum CrossCompileMethod: String, CustomStringConvertible {
    case docker
    case container
    case swiftStaticSdk = "swift-static-sdk"
    case customSdk = "custom-sdk"

    var isSupported: Bool {
        switch self {
        case .docker, .container, .swiftStaticSdk: return true
        case .customSdk: return false
        }
    }

    static func parse(_ value: String?) throws -> Self {
        guard let value else {
            return .docker
        }

        guard let method = CrossCompileMethod(rawValue: value.lowercased()) else {
            throw BuilderErrors.invalidArgument(
                "invalid cross-compile method '\(value)'. Use 'docker', 'container', 'swift-static-sdk', or 'custom-sdk'."
            )
        }

        guard method.isSupported else {
            throw BuilderErrors.unsupportedCrossCompileMethod(method)
        }

        return method
    }

    var description: String {
        self.rawValue
    }
}
