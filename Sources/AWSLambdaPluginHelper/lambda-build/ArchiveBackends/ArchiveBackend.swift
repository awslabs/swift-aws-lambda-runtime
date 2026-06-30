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

/// A strategy for packaging built Lambda executables into a deployable artifact.
///
/// An archive backend owns *what kind of artifact* is produced from the built binaries — today a
/// ZIP package suitable for upload to AWS Lambda, and in the future other formats such as an OCI
/// image. It is the packaging counterpart to ``BuildBackend`` (which owns *how the binaries are
/// built*); the two are selected and sequenced by ``Builder``.
@available(LambdaSwift 2.0, *)
protocol ArchiveBackend {
    /// A human-readable name used in log output (e.g. "zip").
    var name: String { get }

    /// Package the built product executables into deployable artifacts.
    ///
    /// - Parameters:
    ///   - products: A map of product name to the built executable's URL on the host, as returned
    ///     by a ``BuildBackend``.
    ///   - outputDirectory: The directory where the artifacts should be written.
    ///   - verboseLogging: When `true`, emit verbose output for debugging.
    /// - Returns: A map of product name to the produced ``Artifact``.
    func archive(
        products: [String: URL],
        outputDirectory: URL,
        verboseLogging: Bool
    ) throws -> [String: Artifact]
}
