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

/// Builds products inside a container, cross-compiling for Amazon Linux.
///
/// The build *flow* (pull the image, resolve the build output path, run `swift build` per product)
/// is identical across container runtimes; only the argument spelling differs, which is delegated
/// to the injected ``ContainerCLI``. This single backend therefore serves docker, Apple's
/// `container`, and any future runtime with its own ``ContainerCLI``.
@available(LambdaSwift 2.0, *)
struct ContainerBuildBackend: BuildBackend {
    let cli: any ContainerCLI
    let toolPath: URL
    let baseImage: String
    let disableImageUpdate: Bool

    /// The CPU architecture to build for. The container runs as this architecture, so the compiled
    /// binary targets it; recorded in the build manifest and matched against the deploy architecture.
    let architecture: BuildArchitecture

    /// The cross-compile method that selected this backend, retained for error reporting.
    let method: CrossCompileMethod

    var name: String { self.method.rawValue }

    func build(
        packageIdentity: String,
        packageDirectory: URL,
        products: [String],
        buildConfiguration: BuildConfiguration,
        noStrip: Bool,
        verboseLogging: Bool
    ) throws -> [String: URL] {

        // verify the container CLI binary exists at the resolved path
        guard FileManager.default.fileExists(atPath: self.toolPath.path()) else {
            throw BuilderErrors.containerCLINotFound(self.method)
        }

        print("-------------------------------------------------------------------------")
        print("building \"\(packageIdentity)\" in \(self.name)")
        print("-------------------------------------------------------------------------")

        if !self.disableImageUpdate {
            // update the underlying image, if necessary
            print("updating \"\(self.baseImage)\" image")
            try Utils.execute(
                executable: self.toolPath,
                arguments: self.cli.pullArguments(image: self.baseImage, architecture: self.architecture),
                logLevel: verboseLogging ? .debug : .output
            )
        }

        // get the build output path
        let buildOutputPathCommand = "swift build -c \(buildConfiguration.rawValue) --show-bin-path"
        let dockerBuildOutputPath = try Utils.execute(
            executable: self.toolPath,
            arguments: self.cli.runArguments(
                baseImage: self.baseImage,
                architecture: self.architecture,
                workingDirectory: "/workspace",
                mounts: ["\(packageDirectory.path()):/workspace"],
                env: nil,
                command: buildOutputPathCommand
            ),
            logLevel: verboseLogging ? .debug : .silent
        )
        guard let buildPathOutput = dockerBuildOutputPath.split(separator: "\n").last else {
            throw BuilderErrors.failedParsingDockerOutput(dockerBuildOutputPath)
        }
        // Use the stdlib `replacing(_:with:)` rather than Foundation's `replacingOccurrences(of:with:)`
        // so this stays on FoundationEssentials on Linux.
        let buildOutputPath = URL(
            string: String(buildPathOutput).replacing("/workspace/", with: packageDirectory.description)
        )!

        // build the products
        var builtProducts = [String: URL]()
        for product in products {
            print("building \"\(product)\"")
            var buildCommand =
                "swift build -c \(buildConfiguration.rawValue) --product \(product) --static-swift-stdlib"
            if !noStrip {
                buildCommand += " -Xlinker -s"
            }
            if let localPath = ProcessInfo.processInfo.environment["LAMBDA_USE_LOCAL_DEPS"] {
                // when developing locally, we must have the full swift-aws-lambda-runtime project in the container
                // because Examples' Package.swift have a dependency on ../..
                // just like Package.swift's examples assume ../.., we assume we are two levels below the root project
                let slice = packageDirectory.pathComponents.suffix(2)
                try Utils.execute(
                    executable: self.toolPath,
                    arguments: self.cli.runArguments(
                        baseImage: self.baseImage,
                        architecture: self.architecture,
                        workingDirectory: "/workspace/\(slice.joined(separator: "/"))",
                        mounts: ["\(packageDirectory.path())../..:/workspace"],
                        env: ["LAMBDA_USE_LOCAL_DEPS": localPath],
                        command: buildCommand
                    ),
                    logLevel: verboseLogging ? .debug : .output
                )
            } else {
                try Utils.execute(
                    executable: self.toolPath,
                    arguments: self.cli.runArguments(
                        baseImage: self.baseImage,
                        architecture: self.architecture,
                        workingDirectory: "/workspace",
                        mounts: ["\(packageDirectory.path()):/workspace"],
                        env: nil,
                        command: buildCommand
                    ),
                    logLevel: verboseLogging ? .debug : .output
                )
            }
            let productPath = buildOutputPath.appending(path: product)

            guard FileManager.default.fileExists(atPath: productPath.path()) else {
                print("expected '\(product)' binary at \"\(productPath.path())\"")
                throw BuilderErrors.productExecutableNotFound(product)
            }
            builtProducts[product] = productPath
        }
        return builtProducts
    }
}
