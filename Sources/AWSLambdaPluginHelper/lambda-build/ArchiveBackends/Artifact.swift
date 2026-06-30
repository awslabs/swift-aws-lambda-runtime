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

/// A deployable artifact produced by an ``ArchiveBackend``.
///
/// A ZIP package is a file on disk, but an OCI image is an *image reference* in a local container
/// store rather than a file — so the two cannot both be expressed as a single `URL`. This enum lets
/// each backend return whatever shape its format actually produces, and lets `lambda-deploy` branch
/// on the kind of artifact it is handed.
@available(LambdaSwift 2.0, *)
enum Artifact: Equatable, CustomStringConvertible {
    /// A ZIP package at the given path on disk.
    case zip(URL)
    /// A locally-built OCI image, identified by an image reference (e.g. `swift-lambda/MyLambda:latest`).
    case ociImage(reference: String)

    var description: String {
        switch self {
        case .zip(let url):
            return url.path()
        case .ociImage(let reference):
            return reference
        }
    }
}
