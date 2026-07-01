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

        // Build into a dedicated scratch path, NOT the package's default `.build`. This plugin runs
        // as a SwiftPM command plugin, which holds the workspace lock on `.build` for its whole
        // duration; a nested `swift build` targeting the same `.build` would block forever waiting
        // for that lock. A separate scratch path sidesteps the deadlock (the container backend does
        // not hit this because its build runs inside the container, not against the host `.build`).
        let scratchPath = packageDirectory.appending(path: ".build").appending(path: "lambda-static-sdk")

        // Resolve the build output path with the same `--swift-sdk` selector the build uses. This
        // doubles as the SDK preflight: SwiftPM resolves the SDK exactly as a real build would, so
        // if no SDK targets the triple this fails, and we surface actionable install guidance. We
        // cannot download the SDK ourselves (the plugin sandbox limits network to Docker).
        //
        // `swift sdk list` is deliberately NOT used here: it prints SDK bundle identifiers (e.g.
        // `swift-…_static-linux-0.1.0`), which do not contain the target triple, so matching on the
        // triple gives false negatives even when the SDK is installed.
        let binPath: String
        do {
            binPath = try Utils.execute(
                executable: self.swiftToolPath,
                arguments: [
                    "build", "-c", buildConfiguration.rawValue,
                    "--swift-sdk", triple,
                    "--scratch-path", scratchPath.path(),
                    "--show-bin-path",
                ],
                customWorkingDirectory: packageDirectory,
                logLevel: verboseLogging ? .debug : .silent
            ).trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            throw BuilderErrors.staticSDKNotInstalled(triple)
        }
        let buildOutputPath = URL(fileURLWithPath: binPath)

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
                "--scratch-path", scratchPath.path(),
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
