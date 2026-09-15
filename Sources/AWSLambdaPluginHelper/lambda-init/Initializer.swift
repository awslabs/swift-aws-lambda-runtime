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

/// The `SupportedPlatform.MacOSVersion` matching the `LambdaSwift 2.0` availability macro.
private let minimumMacOSVersion = "v15"

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

            // The runtime API is only available on macOS 15 or later. Without the matching
            // platform requirement, the generated function does not compile on macOS.
            try self.addMacOSPlatformRequirement(
                to: configuration.destinationDir,
                verboseLogging: configuration.verboseLogging
            )

            print("📦 You can now package with: 'swift package lambda-build'")
        } catch {
            print("🛑 Failed to create the Lambda function file: \(error)")
            // Re-throw so the SwiftPM plugin observes a non-zero exit status and the
            // failure is not silently swallowed.
            throw error
        }
    }

    /// Adds the macOS platform requirement of `AWSLambdaRuntime` to the package manifest.
    ///
    /// The runtime API is annotated with `@available(LambdaSwift 2.0, *)`, an availability macro
    /// that expands to `macOS 15.0`. A package that does not declare that platform requirement
    /// fails to build on macOS with "is only available in macOS 15.0 or newer".
    ///
    /// `platforms` is set by appending an assignment at the end of the manifest rather than by
    /// inserting an argument into the `Package(...)` call. `Package` is a class, so mutating it
    /// after initialization is valid, and appending needs no parsing of the existing manifest.
    private func addMacOSPlatformRequirement(to destinationDir: URL, verboseLogging: Bool) throws {
        let manifestURL = destinationDir.appendingPathComponent("Package.swift")

        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            print("⚠️  No Package.swift found at \(manifestURL.path).")
            print("   Add 'platforms: [.macOS(.\(minimumMacOSVersion))]' to your package manifest manually.")
            return
        }

        let manifest = try String(contentsOf: manifestURL, encoding: .utf8)

        // Don't override platform requirements the developer already declared.
        let declaresPlatforms = manifest.split(separator: "\n").contains { line in
            let statement = line.trimming(while: \.isWhitespace)
            return statement.hasPrefix("platforms:") || statement.hasPrefix("package.platforms")
        }
        guard !declaresPlatforms else {
            if verboseLogging {
                print("Package.swift already declares platform requirements, leaving it unchanged")
            }
            return
        }

        let existing = manifest.hasSuffix("\n") ? manifest : manifest + "\n"
        try """
        \(existing)
        // The AWSLambdaRuntime API requires macOS 15 or later.
        package.platforms = [
            .macOS(.\(minimumMacOSVersion))
        ]

        """.write(to: manifestURL, atomically: true, encoding: .utf8)

        print("✅ Added 'package.platforms = [.macOS(.\(minimumMacOSVersion))]' to Package.swift")
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
