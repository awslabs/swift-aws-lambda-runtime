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

import Foundation
import PackagePlugin

@main
struct AWSLambdaBuilder: CommandPlugin {

    func performCommand(context: PackagePlugin.PluginContext, arguments: [String]) async throws {

        // This plugin is a thin layer over the AWSLambdaPluginHelper executable. It resolves only
        // the values that require the PackagePlugin sandbox or the package graph, injects them as
        // canonical arguments, then forwards every argument it did not consume to the helper. The
        // helper owns the remaining argument parsing and defaulting.
        var argumentExtractor = ArgumentExtractor(arguments)

        // Options the plugin resolves itself. These are consumed (extracted) here so they are not
        // also forwarded via remainingArguments, which would pass them to the helper twice.
        let outputPathArgument = argumentExtractor.extractOption(named: "output-path")
        let productsArgument = argumentExtractor.extractOption(named: "products")
        // The helper requires --configuration; the plugin supplies the default. Validation of the
        // value itself is left to the helper.
        let configurationArgument = argumentExtractor.extractOption(named: "configuration")
        let crossCompileArgument = argumentExtractor.extractOption(named: "cross-compile")
        // `--container-cli` only exists on the deprecated `archive` command. Reject it here rather
        // than let it fall through to the helper and be silently ignored (which would build with the
        // wrong CLI). The user is told to use the canonical `--cross-compile` instead.
        guard argumentExtractor.extractOption(named: "container-cli").isEmpty else {
            throw BuilderErrors.invalidArgument(
                "'--container-cli' is not supported by lambda-build. Use '--cross-compile <docker|container>' instead."
            )
        }

        // Resolve the tool that matches the requested cross-compilation method. The plugin sandbox
        // can only run tools it resolves up front, so we must pick the right binary here:
        // `swift` for `--cross-compile swift-static-sdk` (no container runtime needed),
        // `container` for `--cross-compile container`, `docker` otherwise.
        let crossCompileMethod = crossCompileArgument.first?.lowercased()
        let crossCompileToolName: String
        switch crossCompileMethod {
        case "swift-static-sdk":
            crossCompileToolName = "swift"
            // The Static Linux SDK builds without a container, so the docker/container-specific
            // options do not apply. Reject them here rather than let them be silently ignored.
            // These flags are forwarded verbatim to the helper, so inspect the raw arguments.
            let incompatibleWithStaticSDK = [
                "--base-docker-image",
                "--swift-version",
                "--disable-docker-image-update",
                "--base-oci-image",
            ]
            for flag in incompatibleWithStaticSDK where arguments.contains(flag) {
                throw BuilderErrors.invalidArgument(
                    "'\(flag)' cannot be used with '--cross-compile swift-static-sdk'; it targets a "
                        + "container-based build. Remove it, or choose '--cross-compile docker' or 'container'."
                )
            }
            // The OCI image build requires a container CLI, so it is incompatible too. Match the
            // value that follows --archive-format rather than a bare "oci" token anywhere.
            if let formatIndex = arguments.firstIndex(of: "--archive-format"),
                arguments.indices.contains(formatIndex + 1),
                arguments[formatIndex + 1].lowercased() == "oci"
            {
                throw BuilderErrors.invalidArgument(
                    "'--archive-format oci' cannot be used with '--cross-compile swift-static-sdk'; "
                        + "building an OCI image requires a container CLI. Use '--cross-compile docker' or 'container'."
                )
            }
        case "container": crossCompileToolName = "container"
        default: crossCompileToolName = "docker"
        }
        let crossCompileToolPath = try context.tool(named: crossCompileToolName).url
        let zipToolPath = try context.tool(named: "zip").url

        // Resolve the output directory. The default lives under the plugin's work directory, whose
        // location is only known to the plugin. This path is part of the plugin's public contract
        // (documented and consumed by lambda-deploy), so it must stay stable.
        let outputDirectory: URL
        if let outputPath = outputPathArgument.first {
            #if os(Linux)
            var isDirectory: Bool = false
            #else
            var isDirectory: ObjCBool = false
            #endif
            guard FileManager.default.fileExists(atPath: outputPath, isDirectory: &isDirectory) else {
                throw BuilderErrors.invalidArgument("invalid output directory '\(outputPath)'")
            }
            outputDirectory = URL(fileURLWithPath: outputPath)
        } else {
            outputDirectory = context.pluginWorkDirectoryURL.appending(path: "\(AWSLambdaBuilder.self)")
        }

        // Resolve and validate the products against the package graph.
        let products: [Product]
        if productsArgument.isEmpty {
            products = context.package.products.filter { $0 is ExecutableProduct }
        } else {
            products = try context.package.products(named: productsArgument)
            for product in products where !(product is ExecutableProduct) {
                throw BuilderErrors.invalidArgument("product named '\(product.name)' is not an executable product")
            }
        }

        let tool = try context.tool(named: "AWSLambdaPluginHelper")
        var args = [
            "build",
            "--output-path", outputDirectory.path(),
            "--products", products.map { $0.name }.joined(separator: ","),
            "--package-id", context.package.id,
            "--package-display-name", context.package.displayName,
            "--package-directory", context.package.directoryURL.path(),
            "--configuration", configurationArgument.first ?? "release",
            "--cross-compile-tool-path", crossCompileToolPath.path,
            "--zip-tool-path", zipToolPath.path,
        ]
        // Re-inject the cross-compilation method (normalised to --cross-compile) so the helper can
        // select the build method, then forward everything the plugin did not consume.
        if let crossCompileMethod {
            args += ["--cross-compile", crossCompileMethod]
        }
        args += argumentExtractor.remainingArguments

        // Invoke the plugin helper, passing the current environment so that
        // AWS credentials and HOME are available to the subprocess.
        let process = Process()
        process.executableURL = tool.url
        process.arguments = args
        process.environment = ProcessInfo.processInfo.environment
        try process.run()
        process.waitUntilExit()

        // Check whether the subprocess invocation was successful.
        if !(process.terminationReason == .exit && process.terminationStatus == 0) {
            let problem = "\(process.terminationReason):\(process.terminationStatus)"
            Diagnostics.error("AWSLambdaPluginHelper invocation failed: \(problem)")
        }
    }
}

private enum BuilderErrors: Error, CustomStringConvertible {
    case invalidArgument(String)

    var description: String {
        switch self {
        case .invalidArgument(let description):
            return description
        }
    }
}

extension PackageManager.BuildResult {
    // find the executable produced by the build
    func executableArtifact(for product: Product) -> PackageManager.BuildResult.BuiltArtifact? {
        let executables = self.builtArtifacts.filter {
            $0.kind == .executable && $0.url.lastPathComponent == product.name
        }
        guard !executables.isEmpty else {
            return nil
        }
        guard executables.count == 1, let executable = executables.first else {
            return nil
        }
        return executable
    }
}
