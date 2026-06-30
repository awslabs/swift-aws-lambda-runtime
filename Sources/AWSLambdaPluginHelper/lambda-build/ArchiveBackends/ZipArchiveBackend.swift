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

/// Packages built executables into ZIP archives suitable for upload to AWS Lambda.
///
/// Each product is laid out as a `bootstrap` executable (the name the Lambda runtime expects)
/// alongside any `*.resources` bundles, then zipped via the `zip` tool.
@available(LambdaSwift 2.0, *)
struct ZipArchiveBackend: ArchiveBackend {
    let name = "zip"

    /// The resolved path to the `zip` tool.
    let zipToolPath: URL

    // TODO: explore using ziplib or similar instead of shelling out
    func archive(
        products: [String: URL],
        outputDirectory: URL,
        verboseLogging: Bool
    ) throws -> [String: Artifact] {

        var archives = [String: Artifact]()
        for (product, artifactPath) in products {
            print("-------------------------------------------------------------------------")
            print("archiving \"\(product)\"")
            print("-------------------------------------------------------------------------")

            // prep zipfile location
            let workingDirectory = outputDirectory.appending(path: product)
            let zipfilePath = workingDirectory.appending(path: "\(product).zip")
            if FileManager.default.fileExists(atPath: workingDirectory.path()) {
                try FileManager.default.removeItem(atPath: workingDirectory.path())
            }
            try FileManager.default.createDirectory(atPath: workingDirectory.path(), withIntermediateDirectories: true)

            // rename artifact to "bootstrap"
            let relocatedArtifactPath = workingDirectory.appending(path: "bootstrap")
            try FileManager.default.copyItem(atPath: artifactPath.path(), toPath: relocatedArtifactPath.path())

            var arguments: [String] = []
            #if os(macOS) || os(Linux)
            arguments = [
                "--recurse-paths",
                "--symlinks",
                zipfilePath.lastPathComponent,
                relocatedArtifactPath.lastPathComponent,
            ]
            #else
            throw BuilderErrors.unsupportedPlatform("can't or don't know how to create a zip file on this platform")
            #endif

            // add resources
            var artifactPathComponents = artifactPath.pathComponents
            _ = artifactPathComponents.removeFirst()  // Get rid of beginning "/"
            _ = artifactPathComponents.removeLast()  // Get rid of the name of the package
            let artifactDirectory = "/\(artifactPathComponents.joined(separator: "/"))"
            for fileInArtifactDirectory in try FileManager.default.contentsOfDirectory(atPath: artifactDirectory) {
                guard let artifactURL = URL(string: "\(artifactDirectory)/\(fileInArtifactDirectory)") else {
                    continue
                }

                guard artifactURL.pathExtension == "resources" else {
                    continue  // Not resources, so don't copy
                }
                let resourcesDirectoryName = artifactURL.lastPathComponent
                let relocatedResourcesDirectory = workingDirectory.appending(path: resourcesDirectoryName)
                if FileManager.default.fileExists(atPath: artifactURL.path()) {
                    do {
                        arguments.append(resourcesDirectoryName)
                        try FileManager.default.copyItem(
                            atPath: artifactURL.path(),
                            toPath: relocatedResourcesDirectory.path()
                        )
                    } catch let error as CocoaError {

                        // On Linux, when the build has been done with Docker,
                        // the source file are owned by root
                        // this causes a permission error **after** the files have been copied
                        // see https://github.com/awslabs/swift-aws-lambda-runtime/issues/449
                        // see https://forums.swift.org/t/filemanager-copyitem-on-linux-fails-after-copying-the-files/77282

                        // because this error happens after the files have been copied, we can ignore it
                        // this code checks if the destination file exists
                        // if they do, just ignore error, otherwise throw it up to the caller.
                        if !(error.code == CocoaError.Code.fileWriteNoPermission
                            && FileManager.default.fileExists(atPath: relocatedResourcesDirectory.path()))
                        {
                            throw error
                        }  // else just ignore it
                    }
                }
            }

            // run the zip tool
            try Utils.execute(
                executable: self.zipToolPath,
                arguments: arguments,
                customWorkingDirectory: workingDirectory,
                logLevel: verboseLogging ? .debug : .silent
            )

            // write the build manifest next to the zip so lambda-deploy has an explicit contract
            // (package type + architecture) instead of re-deriving everything from the path.
            try BuildManifest.zip(
                product: product,
                architecture: .host,
                zipPath: zipfilePath.path()
            ).write(into: workingDirectory)

            archives[product] = .zip(zipfilePath)
        }
        return archives
    }
}
