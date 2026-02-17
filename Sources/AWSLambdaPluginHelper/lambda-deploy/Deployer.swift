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

struct Deployer {

    func deploy(arguments: [String]) async throws {
        let configuration = try DeployerConfiguration(arguments: arguments)

        if configuration.help {
            self.displayHelpMessage()
            return
        }

        //FIXME: use Logger
        print("TODO: deploy")
    }

    private func displayHelpMessage() {
        print(
            """
            OVERVIEW: A SwiftPM plugin to deploy a Lambda function.

            USAGE: swift package lambda-deploy
                                 [--with-url]
                                 [--help] [--verbose]

            OPTIONS:
            --with-url     Add an URL to access the Lambda function          
            --verbose      Produce verbose output for debugging.
            --help         Show help information.
            """
        )
    }
}

private struct DeployerConfiguration: CustomStringConvertible {
    public let help: Bool
    public let verboseLogging: Bool

    public init(arguments: [String]) throws {
        var argumentExtractor = ArgumentExtractor(arguments)
        let verboseArgument = argumentExtractor.extractFlag(named: "verbose") > 0
        let helpArgument = argumentExtractor.extractFlag(named: "help") > 0

        // help required ?
        self.help = helpArgument

        // verbose logging required ?
        self.verboseLogging = verboseArgument
    }

    var description: String {
        """
        {
          verboseLogging: \(self.verboseLogging)
        }
        """
    }
}
