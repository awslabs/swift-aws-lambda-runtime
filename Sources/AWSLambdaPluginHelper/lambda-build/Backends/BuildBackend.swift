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

/// A strategy for building Lambda product executables for the Amazon Linux target.
///
/// A backend owns *how* a build is performed — natively on an Amazon Linux host, inside a
/// container (docker, Apple's `container`, …), or via a Swift cross-compilation SDK. Backend
/// selection lives in ``Builder`` and ``CrossCompileMethod/makeBackend(configuration:)``; the
/// configuration each backend needs (tool paths, base image, …) is injected through its
/// initializer rather than this protocol, so the protocol stays stable as new backends are added.
@available(LambdaSwift 2.0, *)
protocol BuildBackend {
    /// A human-readable name used in log output (e.g. "docker", "container", "native").
    var name: String { get }

    /// Build the requested products and return a map of product name to the built binary's
    /// location on the host filesystem.
    ///
    /// - Parameters:
    ///   - packageIdentity: The package identity, used for log output.
    ///   - packageDirectory: The root directory of the package being built.
    ///   - products: The executable product names to build.
    ///   - buildConfiguration: `debug` or `release`.
    ///   - noStrip: When `true`, debug symbols are not stripped from the binary.
    ///   - verboseLogging: When `true`, emit verbose output for debugging.
    /// - Returns: A map of product name to the built executable's URL on the host.
    func build(
        packageIdentity: String,
        packageDirectory: URL,
        products: [String],
        buildConfiguration: BuildConfiguration,
        noStrip: Bool,
        verboseLogging: Bool
    ) throws -> [String: URL]
}
