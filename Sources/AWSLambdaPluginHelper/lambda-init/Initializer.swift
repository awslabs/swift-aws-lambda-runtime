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

@available(LambdaSwift 2.0, *)
struct Initializer {

    func initialize(arguments: [String]) async throws {

        let configuration = try InitializerConfiguration(arguments: arguments)

        if configuration.help {
            self.displayHelpMessage()
            return
        }

        // Find the main entry point file in the Sources directory
        let sourcesDir = configuration.destinationDir.appendingPathComponent("Sources")
        let entryPoint = try findEntryPoint(in: sourcesDir)

        // Back up the original file
        let backupURL = entryPoint.appendingPathExtension("bak")
        if FileManager.default.fileExists(atPath: entryPoint.path) {
            try? FileManager.default.copyItem(at: entryPoint, to: backupURL)
            if configuration.verboseLogging {
                print("Backed up original file to: \(backupURL.path)")
            }
        }

        // Overwrite with the Lambda template
        do {
            let template = TemplateType.template(for: configuration.templateType)
            try template.write(to: entryPoint, atomically: true, encoding: .utf8)

            if configuration.verboseLogging {
                print("File written at: \(entryPoint.path)")
            }

            // `replacingOccurrences(of:with:)` lives in full Foundation; use the stdlib
            // `replacing(_:with:)` so this stays on FoundationEssentials on Linux.
            let relativePath = entryPoint.path.replacing(
                configuration.destinationDir.path + "/",
                with: ""
            )
            print("✅ Lambda function written to \(relativePath)")
            print("📦 You can now package with: 'swift package lambda-build'")
        } catch {
            print("🛑 Failed to create the Lambda function file: \(error)")
            // Re-throw so the SwiftPM plugin observes a non-zero exit status and the
            // failure is not silently swallowed.
            throw error
        }
    }

    /// Finds the main entry point Swift file in the Sources directory.
    ///
    /// Strategy:
    /// 1. Look for a file containing `@main` or a `main.swift`
    /// 2. If Sources has a single subdirectory, look for `<SubdirName>.swift` in it
    /// 3. Fall back to `Sources/main.swift`
    private func findEntryPoint(in sourcesDir: URL) throws -> URL {
        guard FileManager.default.fileExists(atPath: sourcesDir.path) else {
            // No Sources directory yet — use the classic path
            return sourcesDir.appendingPathComponent("main.swift")
        }

        // List immediate children of Sources/ (path-based helpers keep this off full Foundation).
        let contents = try FileManager.default.visibleContents(of: sourcesDir)

        // Find subdirectories (typical Swift package layout: Sources/<TargetName>/)
        let subdirs = contents.filter { FileManager.default.isDirectory(atPath: $0.path) }

        // If there's exactly one subdirectory, look inside it
        if let targetDir = subdirs.first, subdirs.count == 1 {
            let targetName = targetDir.lastPathComponent

            // Check for main.swift first
            let mainSwift = targetDir.appendingPathComponent("main.swift")
            if FileManager.default.fileExists(atPath: mainSwift.path) {
                return mainSwift
            }

            // Check for <TargetName>.swift (what `swift package init --type executable` creates)
            let namedFile = targetDir.appendingPathComponent("\(targetName).swift")
            if FileManager.default.fileExists(atPath: namedFile.path) {
                return namedFile
            }

            // Look for any .swift file containing @main
            let swiftFiles = try FileManager.default.visibleContents(of: targetDir).filter {
                $0.pathExtension == "swift"
            }

            for file in swiftFiles {
                if let content = try? String(contentsOf: file, encoding: .utf8),
                    content.contains("@main")
                {
                    return file
                }
            }

            // No match found — default to <TargetName>.swift (will be created)
            return namedFile
        }

        // No subdirectory or multiple subdirectories — check for main.swift directly in Sources/
        let mainSwift = sourcesDir.appendingPathComponent("main.swift")
        if FileManager.default.fileExists(atPath: mainSwift.path) {
            return mainSwift
        }

        // Check for any .swift file in Sources/ containing @main
        let topLevelSwiftFiles = contents.filter { $0.pathExtension == "swift" }
        for file in topLevelSwiftFiles {
            if let content = try? String(contentsOf: file, encoding: .utf8),
                content.contains("@main")
            {
                return file
            }
        }

        // Fall back to Sources/main.swift
        return mainSwift
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
