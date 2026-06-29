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

// NOTE: The `@swift-6.4` suffix in this file name is documentation only. Unlike
// `Package@swift-X.Y.swift`, SwiftPM does NOT version-select target/plugin source
// files, so this file is compiled on every toolchain. The `#if swift(>=6.4)` guard
// below is what actually restricts its contents to Swift 6.4+. The Swift < 6.4
// implementation lives in `Plugin.swift` behind the matching `#if swift(<6.4)`.

#if swift(>=6.4)
import Foundation
import PackagePlugin

@main
struct AWSLambdaPackager: CommandPlugin {

    func performCommand(context: PackagePlugin.PluginContext, arguments: [String]) async throws {

        Diagnostics.warning(
            "'archive' is deprecated. Please use 'swift package lambda-build' instead."
        )

        // Resolve context-dependent values (same as AWSLambdaBuilder)
        let outputDirectory: URL
        let products: [Product]
        let buildConfiguration: PackageManager.BuildConfiguration
        let packageID: String = context.package.id
        let packageDisplayName = context.package.displayName
        let packageDirectory = context.package.directoryURL
        let zipToolPath = try context.tool(named: "zip").url

        var argumentExtractor = ArgumentExtractor(arguments)

        let outputPathArgument = argumentExtractor.extractOption(named: "output-path")
        let outputDirectoryArgument = argumentExtractor.extractOption(named: "output-directory")
        let productsArgument = argumentExtractor.extractOption(named: "products")
        let configurationArgument = argumentExtractor.extractOption(named: "configuration")

        // Resolve the container CLI that matches the requested cross-compilation method.
        // The plugin sandbox can only run tools it resolves up front, so we must pick the right
        // binary here — `container` for `container`, `docker` otherwise. Extracting these options
        // only peeks them for the plugin; the original `arguments` (which the helper re-parses) is
        // still forwarded unchanged below. `--container-cli` is the legacy alias for `--cross-compile`.
        let crossCompileArgument = argumentExtractor.extractOption(named: "cross-compile")
        let containerCliArgument = argumentExtractor.extractOption(named: "container-cli")
        let crossCompileMethod = (crossCompileArgument.first ?? containerCliArgument.first)?.lowercased()
        let containerCLIToolName = crossCompileMethod == "container" ? "container" : "docker"
        let containerToolPath = try context.tool(named: containerCLIToolName).url

        // output directory
        if let outputPath = outputPathArgument.first ?? outputDirectoryArgument.first {
            #if os(Linux)
            var isDirectory: Bool = false
            #else
            var isDirectory: ObjCBool = false
            #endif
            guard FileManager.default.fileExists(atPath: outputPath, isDirectory: &isDirectory)
            else {
                throw PackagerErrors.invalidArgument("invalid output directory '\(outputPath)'")
            }
            outputDirectory = URL(fileURLWithPath: outputPath)
        } else {
            outputDirectory = context.pluginWorkDirectoryURL.appending(path: "\(AWSLambdaPackager.self)")
        }

        // products
        let explicitProducts = !productsArgument.isEmpty
        if explicitProducts {
            let _products = try context.package.products(named: productsArgument)
            for product in _products {
                guard product is ExecutableProduct else {
                    throw PackagerErrors.invalidArgument("product named '\(product.name)' is not an executable product")
                }
            }
            products = _products
        } else {
            products = context.package.products.filter { $0 is ExecutableProduct }
        }

        // build configuration
        if let buildConfigurationName = configurationArgument.first {
            guard let _buildConfiguration = PackageManager.BuildConfiguration(rawValue: buildConfigurationName) else {
                throw PackagerErrors.invalidArgument("invalid build configuration named '\(buildConfigurationName)'")
            }
            buildConfiguration = _buildConfiguration
        } else {
            buildConfiguration = .release
        }

        // Build the resolved arguments for the helper
        let tool = try context.tool(named: "AWSLambdaPluginHelper")
        let args =
            [
                "build",
                "--output-path", outputDirectory.path(),
                "--products", products.map { $0.name }.joined(separator: ","),
                "--configuration", buildConfiguration.rawValue,
                "--package-id", packageID,
                "--package-display-name", packageDisplayName,
                "--package-directory", packageDirectory.path(),
                "--docker-tool-path", containerToolPath.path,
                "--zip-tool-path", zipToolPath.path,
            ] + arguments

        // Invoke the plugin helper, passing the current environment
        let process = Process()
        process.executableURL = tool.url
        process.arguments = args
        process.environment = ProcessInfo.processInfo.environment
        try process.run()
        process.waitUntilExit()

        if !(process.terminationReason == .exit && process.terminationStatus == 0) {
            let problem = "\(process.terminationReason):\(process.terminationStatus)"
            Diagnostics.error("AWSLambdaPluginHelper invocation failed: \(problem)")
        }
    }
}

private enum PackagerErrors: Error, CustomStringConvertible {
    case invalidArgument(String)

    var description: String {
        switch self {
        case .invalidArgument(let description):
            return description
        }
    }
}

extension PackageManager.BuildResult {
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
#endif
