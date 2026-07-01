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

/// Cross-compiles products with the Static Linux SDK (musl), producing a statically-linked binary
/// that runs on Amazon Linux without a container runtime.
///
/// Unlike ``ContainerBuildBackend`` this shells out to `swift` directly on the host — no docker or
/// Apple `container` involved. The target architecture is selected with `--swift-sdk <musl-triple>`,
/// so this backend genuinely cross-compiles (e.g. building an arm64 binary on an x64 host and vice
/// versa), independent of the host architecture.
///
/// The SDK must be installed beforehand (`swift sdk install …`). The plugin's network sandbox
/// (`.docker` scope) forbids downloading it at build time, so this backend detects a missing SDK
/// and fails with install guidance rather than attempting to fetch it.
@available(LambdaSwift 2.0, *)
struct StaticLinuxSDKBuildBackend: BuildBackend {
    /// The target CPU architecture, mapped to a musl target triple via ``BuildArchitecture/muslTriple``.
    let architecture: BuildArchitecture

    /// Path to the `swift` executable resolved by the plugin (the toolchain location differs across
    /// hosts, so we never hardcode `/usr/bin/swift` here).
    let swiftToolPath: URL

    let name = "swift-static-sdk"

    func build(
        packageIdentity: String,
        packageDirectory: URL,
        products: [String],
        buildConfiguration: BuildConfiguration,
        noStrip: Bool,
        verboseLogging: Bool
    ) throws -> [String: URL] {

        // verify the swift binary exists at the resolved path
        guard FileManager.default.fileExists(atPath: self.swiftToolPath.path()) else {
            throw BuilderErrors.swiftToolNotFound(self.swiftToolPath.path())
        }

        let triple = self.architecture.muslTriple

        // The plugin sandbox cannot download the SDK (network is limited to Docker), so require it
        // to be installed up front and fail with actionable guidance otherwise.
        try self.verifyStaticSDKInstalled(triple: triple, verboseLogging: verboseLogging)

        print("-------------------------------------------------------------------------")
        print("building \"\(packageIdentity)\" with the Static Linux SDK (\(triple))")
        print("-------------------------------------------------------------------------")

        var builtProducts = [String: URL]()
        for product in products {
            print("building \"\(product)\"")
            var buildArguments = [
                "build", "-c", buildConfiguration.rawValue,
                "--product", product,
                "--swift-sdk", triple,
                "--static-swift-stdlib",
            ]
            if !noStrip {
                buildArguments += ["-Xlinker", "-s"]
            }
            try Utils.execute(
                executable: self.swiftToolPath,
                arguments: buildArguments,
                customWorkingDirectory: packageDirectory,
                logLevel: verboseLogging ? .debug : .output
            )

            // The Static Linux SDK build outputs under `.build/<triple>/<config>`, which differs
            // from a native build, so resolve the path with the same --swift-sdk selector.
            let showBinPathArguments = [
                "build", "-c", buildConfiguration.rawValue,
                "--swift-sdk", triple,
                "--show-bin-path",
            ]
            let binPath = try Utils.execute(
                executable: self.swiftToolPath,
                arguments: showBinPathArguments,
                customWorkingDirectory: packageDirectory,
                logLevel: .silent
            ).trimmingCharacters(in: .whitespacesAndNewlines)

            let productPath = URL(fileURLWithPath: binPath).appending(path: product)
            guard FileManager.default.fileExists(atPath: productPath.path()) else {
                print("expected '\(product)' binary at \"\(productPath.path())\"")
                throw BuilderErrors.productExecutableNotFound(product)
            }
            builtProducts[product] = productPath
        }
        return builtProducts
    }

    /// Confirms a Static Linux SDK targeting `triple` is installed by scanning `swift sdk list`.
    ///
    /// Matches leniently on the triple substring rather than a pinned SDK name/version: the SDK
    /// identifier varies across Swift releases, and pinning would force per-toolchain maintenance.
    private func verifyStaticSDKInstalled(triple: String, verboseLogging: Bool) throws {
        let installed = try Utils.execute(
            executable: self.swiftToolPath,
            arguments: ["sdk", "list"],
            logLevel: verboseLogging ? .debug : .silent
        )
        guard installed.contains(triple) else {
            throw BuilderErrors.staticSDKNotInstalled(triple)
        }
    }
}
