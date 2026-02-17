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

struct Initializer {

    private let destFileName = "Sources/main.swift"

    func initialize(arguments: [String]) async throws {

        let configuration = try InitializerConfiguration(arguments: arguments)

        if configuration.help {
            self.displayHelpMessage()
            return
        }

        let destFileURL = configuration.destinationDir.appendingPathComponent(destFileName)
        do {

            let template = TemplateType.template(for: configuration.templateType)
            try template.write(to: destFileURL, atomically: true, encoding: .utf8)

            if configuration.verboseLogging {
                print("File created at: \(destFileURL)")
            }

            print("✅ Lambda function written to \(destFileName)")
            print("📦 You can now package with: 'swift package lambda-build'")
        } catch {
            print("🛑Failed to create the Lambda function file: \(error)")
        }
    }

    private func displayHelpMessage() {
        print(
            """
            OVERVIEW: A SwiftPM plugin to scaffold a HelloWorld Lambda function.
                      By default, it creates a Lambda function that receives a JSON 
                      document and responds with another JSON document.

            USAGE: swift package lambda-init
                                 [--help] [--verbose]
                                 [--with-url]
                                 [--allow-writing-to-package-directory]

            OPTIONS:
            --with-url                            Create a Lambda function exposed with an URL
            --allow-writing-to-package-directory  Don't ask for permissions to write files.
            --verbose                             Produce verbose output for debugging.
            --help                                Show help information.
            """
        )
    }
}

private enum TemplateType {
    case `default`
    case url

    static func template(for type: TemplateType) -> String {
        switch type {
        case .default: return functionWithJSONTemplate
        case .url: return functionWithUrlTemplate
        }
    }
}

private struct InitializerConfiguration: CustomStringConvertible {
    public let help: Bool
    public let verboseLogging: Bool
    public let destinationDir: URL
    public let templateType: TemplateType

    public init(arguments: [String]) throws {
        var argumentExtractor = ArgumentExtractor(arguments)
        let verboseArgument = argumentExtractor.extractFlag(named: "verbose") > 0
        let helpArgument = argumentExtractor.extractFlag(named: "help") > 0
        let destDirArgument = argumentExtractor.extractOption(named: "dest-dir")
        let templateURLArgument = argumentExtractor.extractFlag(named: "with-url") > 0

        // help required ?
        self.help = helpArgument

        // verbose logging required ?
        self.verboseLogging = verboseArgument

        // dest dir
        self.destinationDir = URL(fileURLWithPath: destDirArgument[0])

        // template type. Default is the JSON one
        self.templateType = templateURLArgument ? .url : .default
    }

    var description: String {
        """
        {
          verboseLogging: \(self.verboseLogging)
          destinationDir: \(self.destinationDir)
          templateType: \(self.templateType)
        }
        """
    }
}
