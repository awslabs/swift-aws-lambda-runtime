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
        let args = CommandLine.arguments
        let helper = AWSLambdaPluginHelper()
        let command = try helper.command(from: args)
        switch command {
        case .`init`:
            try await Initializer().initialize(arguments: args)
        case .build:
            try await Builder().build(arguments: args)
        case .deploy:
            try await Deployer().deploy(arguments: args)
        }
    }

    private func command(from arguments: [String]) throws -> Command {
        let args = CommandLine.arguments

        guard args.count > 2 else {
            throw AWSLambdaPluginHelperError.noCommand
        }
        let commandName = args[1]
        guard let command = Command(rawValue: commandName) else {
            throw AWSLambdaPluginHelperError.invalidCommand(commandName)
        }

        return command
    }
}

private enum AWSLambdaPluginHelperError: Error {
    case noCommand
    case invalidCommand(String)
}
