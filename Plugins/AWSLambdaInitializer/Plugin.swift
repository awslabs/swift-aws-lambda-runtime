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
        let tool = try context.tool(named: "AWSLambdaPluginHelper")

        let args = ["init", "--dest-dir", context.package.directoryURL.path()] + arguments

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
}
