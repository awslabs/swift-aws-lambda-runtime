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
struct AWSLambdaPackager: CommandPlugin {

    func performCommand(context: PackagePlugin.PluginContext, arguments: [String]) async throws {

        // values to pass to the AWSLambdaPluginHelper
        let outputDirectory: URL
        let products: [Product]
        let buildConfiguration: PackageManager.BuildConfiguration
        let packageID: String = context.package.id
        let packageDisplayName = context.package.displayName
        let packageDirectory = context.package.directoryURL
        let dockerToolPath = try context.tool(named: "docker").url
        let zipToolPath = try context.tool(named: "zip").url

        // extract arguments that require PluginContext to fully resolve
        // resolve them here and pass them to the AWSLambdaPluginHelper as arguments
        var argumentExtractor = ArgumentExtractor(arguments)

        let outputPathArgument = argumentExtractor.extractOption(named: "output-path")
        let productsArgument = argumentExtractor.extractOption(named: "products")
        let configurationArgument = argumentExtractor.extractOption(named: "configuration")

        if let outputPath = outputPathArgument.first {
            #if os(Linux)
            var isDirectory: Bool = false
            #else
            var isDirectory: ObjCBool = false
            #endif
            guard FileManager.default.fileExists(atPath: outputPath, isDirectory: &isDirectory)
            else {
                throw BuilderErrors.invalidArgument("invalid output directory '\(outputPath)'")
            }
            outputDirectory = URL(string: outputPath)!
        } else {
            outputDirectory = context.pluginWorkDirectoryURL.appending(path: "\(AWSLambdaPackager.self)")
        }

        let explicitProducts = !productsArgument.isEmpty
        if explicitProducts {
            let _products = try context.package.products(named: productsArgument)
            for product in _products {
                guard product is ExecutableProduct else {
                    throw BuilderErrors.invalidArgument("product named '\(product.name)' is not an executable product")
                }
            }
            products = _products

        } else {
            products = context.package.products.filter { $0 is ExecutableProduct }
        }

        if let _buildConfigurationName = configurationArgument.first {
            guard let _buildConfiguration = PackageManager.BuildConfiguration(rawValue: _buildConfigurationName) else {
                throw BuilderErrors.invalidArgument("invalid build configuration named '\(_buildConfigurationName)'")
            }
            buildConfiguration = _buildConfiguration
        } else {
            buildConfiguration = .release
        }

        // TODO: When running on Amazon Linux 2, we have to build directly from the plugin
        // launch the build, then call the helper just for the ZIP part

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
                "--docker-tool-path", dockerToolPath.path,
                "--zip-tool-path", zipToolPath.path,
            ] + arguments

        // Invoke the plugin helper on the target directory, passing a configuration
        // file from the package directory.
        let process = try Process.run(tool.url, arguments: args)
        process.waitUntilExit()

        // Check whether the subprocess invocation was successful.
        if !(process.terminationReason == .exit && process.terminationStatus == 0) {
            let problem = "\(process.terminationReason):\(process.terminationStatus)"
            Diagnostics.error("AWSLambdaPluginHelper invocation failed: \(problem)")
        }
    }

    // TODO: When running on Amazon Linux 2, we have to build directly from the plugin
    //    private func build(
    //        packageIdentity: Package.ID,
    //        products: [Product],
    //        buildConfiguration: PackageManager.BuildConfiguration,
    //        verboseLogging: Bool
    //    ) throws -> [LambdaProduct: URL] {
    //        print("-------------------------------------------------------------------------")
    //        print("building \"\(packageIdentity)\"")
    //        print("-------------------------------------------------------------------------")
    //
    //        var results = [LambdaProduct: URL]()
    //        for product in products {
    //            print("building \"\(product.name)\"")
    //            var parameters = PackageManager.BuildParameters()
    //            parameters.configuration = buildConfiguration
    //            parameters.otherSwiftcFlags = ["-static-stdlib"]
    //            parameters.logging = verboseLogging ? .verbose : .concise
    //
    //            let result = try packageManager.build(
    //                .product(product.name),
    //                parameters: parameters
    //            )
    //            guard let artifact = result.executableArtifact(for: product) else {
    //                throw Errors.productExecutableNotFound(product.name)
    //            }
    //            results[.init(product)] = artifact.url
    //        }
    //        return results
    //    }

    //    private func isAmazonLinux2() -> Bool {
    //         if let data = FileManager.default.contents(atPath: "/etc/system-release"),
    //             let release = String(data: data, encoding: .utf8)
    //         {
    //             return release.hasPrefix("Amazon Linux release 2")
    //         } else {
    //             return false
    //         }
    //     }
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
