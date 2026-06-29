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

@main
@available(LambdaSwift 2.0, *)
struct AWSLambdaPluginHelper {

    private enum Command: String {
        case `init`
        case build
        case deploy
    }

    public static func main() async throws {
        // Stream output line-by-line; SwiftPM connects the plugin's stdout to a pipe, which the C
        // runtime would otherwise block-buffer until the process exits.
        enableLineBufferedStdout()

        let args = CommandLine.arguments
        let helper = AWSLambdaPluginHelper()

        guard let command = helper.command(from: args) else {
            helper.displayHelpMessage()
            return
        }

        switch command {
        case .`init`:
            try await Initializer().initialize(arguments: args)
        case .build:
            try await Builder().build(arguments: args)
        case .deploy:
            try await Deployer().deploy(arguments: args)
        }
    }

    /// Returns nil when help should be displayed (no args, "help", "--help", or invalid command).
    private func command(from arguments: [String]) -> Command? {
        let args = arguments

        guard args.count > 1 else {
            return nil
        }

        let commandName = args[1]

        if commandName == "help" || commandName == "--help" || commandName == "-h" {
            return nil
        }

        return Command(rawValue: commandName)
    }

    private func displayHelpMessage() {
        print(
            """
            OVERVIEW: AWS Lambda Plugin Helper

            A shared helper executable for the Swift AWS Lambda Runtime plugins.
            This tool is normally invoked by SwiftPM plugins (lambda-init, lambda-build,
            lambda-deploy) and not called directly.

            USAGE: AWSLambdaPluginHelper <command> [options]

            COMMANDS:
              init      Scaffold a new Lambda function from a template.
              build     Compile and package the Lambda function for deployment.
              deploy    Deploy the packaged Lambda function to AWS.

            Use 'AWSLambdaPluginHelper <command> --help' for more information about a command.

            SWIFTPM PLUGIN USAGE:
              swift package lambda-init --allow-writing-to-package-directory [--with-url]
              swift package --allow-network-connections docker lambda-build [options]
              swift package --allow-network-connections all:443 lambda-deploy [options]
            """
        )
    }
}
