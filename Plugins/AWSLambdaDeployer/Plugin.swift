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
struct AWSLambdaDeployer: CommandPlugin {

    func performCommand(context: PackagePlugin.PluginContext, arguments: [String]) async throws {

        let tool = try context.tool(named: "AWSLambdaPluginHelper")

        // Resolve products: use --products if provided, otherwise default to all executable targets.
        // --products is consumed (extracted) here so it is not also forwarded via remainingArguments,
        // which would pass it to the helper twice.
        var argumentExtractor = ArgumentExtractor(arguments)
        let productsArgument = argumentExtractor.extractOption(named: "products")

        let products: [Product]
        if !productsArgument.isEmpty {
            products = try context.package.products(named: productsArgument)
        } else {
            products = context.package.products.filter { $0 is ExecutableProduct }
        }

        let productNames = products.map { $0.name }.joined(separator: ",")

        let args = ["deploy", "--products", productNames] + argumentExtractor.remainingArguments

        // Invoke the plugin helper, passing the current environment so that
        // AWS credentials (env vars, HOME for ~/.aws/credentials) are available.
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
