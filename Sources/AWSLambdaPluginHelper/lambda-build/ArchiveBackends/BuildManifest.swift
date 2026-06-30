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

/// The explicit hand-off contract between `lambda-build` and `lambda-deploy`.
///
/// A ZIP artifact is fully described by its path on disk, so deploy historically re-derived
/// everything from a hardcoded path convention. An OCI artifact is *not* a file — it is a local
/// image reference plus the architecture and container CLI it was built with, none of which is
/// recoverable from a path. `lambda-build` therefore writes this descriptor next to the build
/// output, and `lambda-deploy` reads it to decide how to deploy.
///
/// Backwards compatible: when no manifest is found, deploy falls back to the legacy path convention
/// and assumes a ZIP package, so existing flows keep working.
@available(LambdaSwift 2.0, *)
struct BuildManifest: Codable, Equatable {
    /// The package type the artifact deploys as.
    enum PackageType: String, Codable {
        case zip
        case image
    }

    /// The schema version of this manifest. Bumped when the shape changes incompatibly.
    let schemaVersion: Int

    /// The product (executable target) this manifest describes.
    let product: String

    /// Whether the artifact deploys as a ZIP package or a container image.
    let packageType: PackageType

    /// The CPU architecture the artifact was built for.
    let architecture: BuildArchitecture

    /// The container CLI used to build the image (`docker` / `container`); `nil` for ZIP artifacts.
    let containerCLI: String?

    /// The path to the ZIP package on disk; set only for `packageType == .zip`.
    let zipPath: String?

    /// The local image tag (e.g. `swift-lambda/MyLambda:latest`); set only for
    /// `packageType == .image`. The ECR-qualified reference and the index-unwrapped child digest are
    /// resolved at deploy time, after the push, so they are deliberately not recorded here.
    let imageTag: String?

    /// The current manifest schema version.
    static let currentSchemaVersion = 1

    /// The filename written into a product's output directory.
    static let fileName = "build-manifest.json"

    /// A manifest for a ZIP artifact.
    static func zip(product: String, architecture: BuildArchitecture, zipPath: String) -> BuildManifest {
        BuildManifest(
            schemaVersion: currentSchemaVersion,
            product: product,
            packageType: .zip,
            architecture: architecture,
            containerCLI: nil,
            zipPath: zipPath,
            imageTag: nil
        )
    }

    /// A manifest for an OCI image artifact.
    static func image(
        product: String,
        architecture: BuildArchitecture,
        containerCLI: String,
        imageTag: String
    ) -> BuildManifest {
        BuildManifest(
            schemaVersion: currentSchemaVersion,
            product: product,
            packageType: .image,
            architecture: architecture,
            containerCLI: containerCLI,
            zipPath: nil,
            imageTag: imageTag
        )
    }

    /// Encodes the manifest and writes it as `build-manifest.json` inside `directory`.
    func write(into directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: directory.appending(path: Self.fileName))
    }

    /// Reads and decodes a `build-manifest.json` from `directory`, or returns `nil` if absent.
    static func read(from directory: URL) throws -> BuildManifest? {
        let url = directory.appending(path: fileName)
        guard FileManager.default.fileExists(atPath: url.path()) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(BuildManifest.self, from: data)
    }
}
