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

/// Packages built executables into an OCI image suitable for deployment as an `Image` Lambda
/// function.
///
/// For each product this backend lays out a build context (the `bootstrap` executable plus any
/// `*.resources` bundles), generates a minimal Dockerfile, and runs `<cli> build` through the
/// resolved container CLI (docker or Apple's `container`). The result is a *locally* tagged image —
/// pushing it to Amazon ECR and creating/updating the function happens later, at deploy time, which
/// is the only step that holds AWS credentials and network access.
@available(LambdaSwift 2.0, *)
struct OCIArchiveBackend: ArchiveBackend {
    let name = "oci"

    /// The container CLI argument flavor (docker / Apple `container`).
    let cli: any ContainerCLI

    /// The resolved path to the container CLI executable.
    let toolPath: URL

    /// The single architecture baked into the image. A Lambda `Image` function declares exactly one
    /// architecture, so the image must be built for exactly one.
    let architecture: BuildArchitecture

    /// The base image the generated Dockerfile builds `FROM` (overridable via `--base-oci-image`).
    let baseImage: String

    /// The default base image: minimal Amazon Linux 2023.
    ///
    /// We deliberately do *not* default to `provided.al2023`: our compiled `bootstrap` already speaks
    /// the Lambda Runtime API (so we are our own runtime interface client), and `provided.al2023`'s
    /// only Lambda-specific content is the Runtime Interface Emulator, documented for local testing
    /// only. A minimal AL2023 base is smaller, has fewer layers, and gives glibc parity with the
    /// `swift:*-amazonlinux2023` build image.
    static let defaultBaseImage = "public.ecr.aws/amazonlinux/amazonlinux:2023-minimal"

    /// The directory inside the image that holds the runtime binary and its resources.
    static let runtimeDirectory = "/var/runtime"

    /// The path the compiled binary is copied to inside the image, and the image's entrypoint.
    static let bootstrapPath = "\(runtimeDirectory)/bootstrap"

    func archive(
        products: [String: URL],
        outputDirectory: URL,
        verboseLogging: Bool
    ) throws -> [String: Artifact] {

        var artifacts = [String: Artifact]()
        for (product, artifactPath) in products {
            print("-------------------------------------------------------------------------")
            print("building OCI image for \"\(product)\"")
            print("-------------------------------------------------------------------------")

            // prepare a clean build-context directory under the output directory
            let contextDirectory = outputDirectory.appending(path: product)
            if FileManager.default.fileExists(atPath: contextDirectory.path()) {
                try FileManager.default.removeItem(atPath: contextDirectory.path())
            }
            try FileManager.default.createDirectory(
                atPath: contextDirectory.path(),
                withIntermediateDirectories: true
            )

            // copy the built binary into the context as "bootstrap" (the name the runtime expects)
            let relocatedArtifactPath = contextDirectory.appending(path: "bootstrap")
            try FileManager.default.copyItem(atPath: artifactPath.path(), toPath: relocatedArtifactPath.path())

            // copy any "*.resources" bundles alongside it, returning their names for the Dockerfile
            let resourceDirectoryNames = try self.copyResources(
                besideArtifact: artifactPath,
                into: contextDirectory
            )

            // write the Dockerfile into the context
            let dockerfilePath = contextDirectory.appending(path: "Dockerfile")
            let dockerfile = self.dockerfileContents(resourceDirectoryNames: resourceDirectoryNames)
            try Data(dockerfile.utf8).write(to: dockerfilePath)

            // build the image, tagged locally; the push to ECR happens at deploy time
            let tag = Self.imageTag(for: product)
            try Utils.execute(
                executable: self.toolPath,
                arguments: self.cli.buildImageArguments(
                    dockerfile: dockerfilePath.path(),
                    contextDir: contextDirectory.path(),
                    tag: tag,
                    architecture: self.architecture
                ),
                logLevel: verboseLogging ? .debug : .output
            )

            // write the build manifest: deploy needs the local tag, the CLI that built the image,
            // and the baked-in architecture to push and create the Image function. The ECR-qualified
            // reference and child-manifest digest are resolved at deploy time, after the push.
            try BuildManifest.image(
                product: product,
                architecture: self.architecture,
                containerCLI: self.cli.executableName,
                imageTag: tag
            ).write(into: contextDirectory)

            artifacts[product] = .ociImage(reference: tag)
        }
        return artifacts
    }

    /// The local image tag applied to a product's image (e.g. `swift-lambda/mylambda:latest`).
    ///
    /// OCI/Docker image reference names must be lowercase, so the product name is lowercased for the
    /// repository component (the function itself keeps its original-case name).
    static func imageTag(for product: String) -> String {
        "swift-lambda/\(product.lowercased()):latest"
    }

    /// The contents of the generated Dockerfile.
    ///
    /// The image starts from the configured base (a minimal Amazon Linux 2023 image by default),
    /// copies the `bootstrap` binary (and any resources bundles) into `/var/runtime`, and runs
    /// `bootstrap` as the entrypoint. No `USER` is set, so it runs as the default Lambda user; the
    /// binary is world-readable and runnable on a read-only filesystem with a writable `/tmp`.
    func dockerfileContents(resourceDirectoryNames: [String]) -> String {
        var lines: [String] = [
            "FROM \(self.baseImage)",
            "COPY bootstrap \(Self.bootstrapPath)",
        ]
        for resourceDirectoryName in resourceDirectoryNames.sorted() {
            lines.append("COPY \(resourceDirectoryName) \(Self.runtimeDirectory)/\(resourceDirectoryName)")
        }
        lines.append("ENTRYPOINT [\"\(Self.bootstrapPath)\"]")
        return lines.joined(separator: "\n") + "\n"
    }

    /// Copies every `*.resources` bundle found beside the built artifact into `contextDirectory`,
    /// returning the copied directory names.
    private func copyResources(besideArtifact artifactPath: URL, into contextDirectory: URL) throws -> [String] {
        var artifactPathComponents = artifactPath.pathComponents
        _ = artifactPathComponents.removeFirst()  // drop leading "/"
        _ = artifactPathComponents.removeLast()  // drop the binary's own name
        let artifactDirectory = "/\(artifactPathComponents.joined(separator: "/"))"

        var copied: [String] = []
        for fileInArtifactDirectory in try FileManager.default.contentsOfDirectory(atPath: artifactDirectory) {
            guard let artifactURL = URL(string: "\(artifactDirectory)/\(fileInArtifactDirectory)") else {
                continue
            }
            guard artifactURL.pathExtension == "resources" else {
                continue  // not a resources bundle, skip
            }
            let resourcesDirectoryName = artifactURL.lastPathComponent
            let relocatedResourcesDirectory = contextDirectory.appending(path: resourcesDirectoryName)
            guard FileManager.default.fileExists(atPath: artifactURL.path()) else { continue }
            do {
                try FileManager.default.copyItem(
                    atPath: artifactURL.path(),
                    toPath: relocatedResourcesDirectory.path()
                )
                copied.append(resourcesDirectoryName)
            } catch let error as CocoaError {
                // On Linux, Docker-built outputs are root-owned; copyItem reports a write-permission
                // error *after* the files are copied. If the destination exists, ignore it.
                // See https://github.com/awslabs/swift-aws-lambda-runtime/issues/449
                if error.code == CocoaError.Code.fileWriteNoPermission
                    && FileManager.default.fileExists(atPath: relocatedResourcesDirectory.path())
                {
                    copied.append(resourcesDirectoryName)
                } else {
                    throw error
                }
            }
        }
        return copied
    }
}
