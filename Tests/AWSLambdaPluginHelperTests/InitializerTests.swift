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

import Testing

@testable import AWSLambdaPluginHelper

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Tests for the `lambda-init` plugin.
///
/// Every test drives the real `Initializer.initialize(arguments:)` entry point against a throwaway
/// package directory on disk and asserts on the resulting files, so the tests cover the plugin as
/// a whole rather than its internals.
@Suite("lambda-init plugin")
struct InitializerTests {

    // MARK: - The generated function

    @available(LambdaSwift 2.0, *)
    @Test("Writes the JSON template over the existing entry point")
    func writesJSONTemplate() async throws {
        try await withTemporaryPackage(sources: ["MyLambda/MyLambda.swift": "print(\"placeholder\")\n"]) { package in
            try await runLambdaInit(in: package)

            let entryPoint = try contents(of: package, at: "Sources/MyLambda/MyLambda.swift")
            #expect(entryPoint == functionWithJSONTemplate)
        }
    }

    @available(LambdaSwift 2.0, *)
    @Test("--with-url writes the FunctionURL template")
    func writesFunctionURLTemplate() async throws {
        try await withTemporaryPackage(sources: ["MyLambda/MyLambda.swift": "print(\"placeholder\")\n"]) { package in
            try await runLambdaInit(in: package, arguments: ["--with-url"])

            let entryPoint = try contents(of: package, at: "Sources/MyLambda/MyLambda.swift")
            #expect(entryPoint == functionWithUrlTemplate)
        }
    }

    @available(LambdaSwift 2.0, *)
    @Test("Backs up the entry point it overwrites")
    func backsUpTheEntryPoint() async throws {
        let original = "print(\"placeholder\")\n"
        try await withTemporaryPackage(sources: ["MyLambda/MyLambda.swift": original]) { package in
            try await runLambdaInit(in: package)

            let backup = try contents(of: package, at: "Sources/MyLambda/MyLambda.swift.bak")
            #expect(backup == original)
        }
    }

    // MARK: - Entry point discovery

    @available(LambdaSwift 2.0, *)
    @Test("Prefers main.swift inside the target directory and leaves other files alone")
    func prefersMainSwiftInTargetDirectory() async throws {
        let sources = [
            "MyLambda/main.swift": "print(\"placeholder\")\n",
            "MyLambda/Helper.swift": "let helper = 1\n",
        ]
        try await withTemporaryPackage(sources: sources) { package in
            try await runLambdaInit(in: package)

            #expect(try contents(of: package, at: "Sources/MyLambda/main.swift") == functionWithJSONTemplate)
            #expect(try contents(of: package, at: "Sources/MyLambda/Helper.swift") == "let helper = 1\n")
        }
    }

    @available(LambdaSwift 2.0, *)
    @Test("Uses the file declaring @main")
    func usesTheFileDeclaringMain() async throws {
        let sources = [
            "MyLambda/Entry.swift": "@main\nstruct Entry {\n    static func main() {}\n}\n",
            "MyLambda/Helper.swift": "let helper = 1\n",
        ]
        try await withTemporaryPackage(sources: sources) { package in
            try await runLambdaInit(in: package)

            #expect(try contents(of: package, at: "Sources/MyLambda/Entry.swift") == functionWithJSONTemplate)
            #expect(try contents(of: package, at: "Sources/MyLambda/Helper.swift") == "let helper = 1\n")
        }
    }

    @available(LambdaSwift 2.0, *)
    @Test("Creates <TargetName>.swift when the target directory has no recognizable entry point")
    func createsNamedFileWhenNoEntryPointExists() async throws {
        try await withTemporaryPackage(sources: ["MyLambda/Helper.swift": "let helper = 1\n"]) { package in
            try await runLambdaInit(in: package)

            #expect(try contents(of: package, at: "Sources/MyLambda/MyLambda.swift") == functionWithJSONTemplate)
        }
    }

    @available(LambdaSwift 2.0, *)
    @Test("Handles Sources/main.swift without a target subdirectory")
    func handlesFlatSourcesLayout() async throws {
        try await withTemporaryPackage(sources: ["main.swift": "print(\"placeholder\")\n"]) { package in
            try await runLambdaInit(in: package)

            #expect(try contents(of: package, at: "Sources/main.swift") == functionWithJSONTemplate)
        }
    }

    @available(LambdaSwift 2.0, *)
    @Test("Falls back to Sources/main.swift when several targets are present")
    func fallsBackToSourcesMainSwiftWithSeveralTargets() async throws {
        let sources = [
            "TargetA/a.swift": "let a = 1\n",
            "TargetB/b.swift": "let b = 2\n",
        ]
        try await withTemporaryPackage(sources: sources) { package in
            try await runLambdaInit(in: package)

            #expect(try contents(of: package, at: "Sources/main.swift") == functionWithJSONTemplate)
            #expect(try contents(of: package, at: "Sources/TargetA/a.swift") == "let a = 1\n")
            #expect(try contents(of: package, at: "Sources/TargetB/b.swift") == "let b = 2\n")
        }
    }

    // MARK: - The macOS platform requirement

    @available(LambdaSwift 2.0, *)
    @Test("Appends the macOS platform requirement to the manifest")
    func appendsPlatformRequirement() async throws {
        try await withTemporaryPackage { package in
            try await runLambdaInit(in: package)

            let manifest = try contents(of: package, at: "Package.swift")
            #expect(manifest == Self.manifestWithoutPlatforms + "\n" + Self.platformRequirement + "\n")
        }
    }

    @available(LambdaSwift 2.0, *)
    @Test("Appends the platform requirement when the manifest has no trailing newline")
    func appendsPlatformRequirementWithoutTrailingNewline() async throws {
        let source = String(Self.manifestWithoutPlatforms.dropLast())
        try await withTemporaryPackage(manifest: source) { package in
            try await runLambdaInit(in: package)

            let manifest = try contents(of: package, at: "Package.swift")
            // The assignment must land on its own line, not glued to the closing parenthesis.
            #expect(manifest == source + "\n\n" + Self.platformRequirement + "\n")
        }
    }

    @available(LambdaSwift 2.0, *)
    @Test("Running twice does not duplicate the platform requirement")
    func platformRequirementIsIdempotent() async throws {
        try await withTemporaryPackage { package in
            try await runLambdaInit(in: package)
            let afterFirstRun = try contents(of: package, at: "Package.swift")

            try await runLambdaInit(in: package)
            let afterSecondRun = try contents(of: package, at: "Package.swift")

            #expect(afterSecondRun == afterFirstRun)
        }
    }

    @available(LambdaSwift 2.0, *)
    @Test("Leaves a manifest that already declares platforms untouched")
    func leavesExistingPlatformsDeclarationUntouched() async throws {
        let source = Self.manifestWithoutPlatforms.replacing(
            "    name: \"MyLambda\",\n",
            with: "    name: \"MyLambda\",\n    platforms: [.macOS(.v15)],\n"
        )
        try await withTemporaryPackage(manifest: source) { package in
            try await runLambdaInit(in: package)

            #expect(try contents(of: package, at: "Package.swift") == source)
        }
    }

    @available(LambdaSwift 2.0, *)
    @Test("Leaves an existing package.platforms assignment untouched")
    func leavesExistingAssignmentUntouched() async throws {
        let source = Self.manifestWithoutPlatforms + "\npackage.platforms = [.macOS(.v26)]\n"
        try await withTemporaryPackage(manifest: source) { package in
            try await runLambdaInit(in: package)

            #expect(try contents(of: package, at: "Package.swift") == source)
        }
    }

    @available(LambdaSwift 2.0, *)
    @Test("Still writes the function when Package.swift is missing")
    func toleratesMissingManifest() async throws {
        try await withTemporaryPackage(
            manifest: nil,
            sources: ["MyLambda/MyLambda.swift": "print(\"placeholder\")\n"]
        ) { package in
            try await runLambdaInit(in: package)

            #expect(try contents(of: package, at: "Sources/MyLambda/MyLambda.swift") == functionWithJSONTemplate)
            #expect(!FileManager.default.fileExists(atPath: package.appending(path: "Package.swift").path))
        }
    }

    // MARK: - Arguments

    @available(LambdaSwift 2.0, *)
    @Test("--help leaves the package untouched")
    func helpLeavesThePackageUntouched() async throws {
        let entryPoint = "print(\"placeholder\")\n"
        try await withTemporaryPackage(sources: ["MyLambda/MyLambda.swift": entryPoint]) { package in
            try await runLambdaInit(in: package, arguments: ["--help"])

            #expect(try contents(of: package, at: "Package.swift") == Self.manifestWithoutPlatforms)
            #expect(try contents(of: package, at: "Sources/MyLambda/MyLambda.swift") == entryPoint)
        }
    }

    @available(LambdaSwift 2.0, *)
    @Test("--verbose does not change the outcome")
    func verboseDoesNotChangeTheOutcome() async throws {
        try await withTemporaryPackage(sources: ["MyLambda/MyLambda.swift": "print(\"placeholder\")\n"]) { package in
            try await runLambdaInit(in: package, arguments: ["--verbose"])

            #expect(try contents(of: package, at: "Sources/MyLambda/MyLambda.swift") == functionWithJSONTemplate)
            #expect(try contents(of: package, at: "Package.swift").hasSuffix(Self.platformRequirement + "\n"))
        }
    }

    // MARK: - Fixtures

    /// What `swift package init --type executable --name MyLambda` produces, plus the runtime
    /// dependency added by `swift package add-dependency`. It declares no platform requirement.
    private static let manifestWithoutPlatforms = """
        // swift-tools-version: 6.2
        import PackageDescription

        let package = Package(
            name: "MyLambda",
            dependencies: [
                .package(url: "https://github.com/awslabs/swift-aws-lambda-runtime.git", from: "3.0.0")
            ],
            targets: [
                .executableTarget(
                    name: "MyLambda",
                    dependencies: [
                        .product(name: "AWSLambdaRuntime", package: "swift-aws-lambda-runtime")
                    ]
                )
            ]
        )

        """

    /// The block the plugin is expected to append. Spelled out here on purpose: the test has to
    /// fail when the generated manifest changes shape.
    private static let platformRequirement = """
        // The AWSLambdaRuntime API requires macOS 15 or later.
        package.platforms = [
            .macOS(.v15)
        ]
        """

    // MARK: - Helpers

    /// Creates a package directory in a unique temporary location, runs `body`, then deletes it.
    ///
    /// - Parameters:
    ///   - manifest: The content of `Package.swift`, or `nil` to leave the manifest out.
    ///   - sources: File contents keyed by their path relative to `Sources/`. Pass an empty
    ///     dictionary to leave the `Sources` directory out.
    @available(LambdaSwift 2.0, *)
    private func withTemporaryPackage(
        manifest: String? = Self.manifestWithoutPlatforms,
        sources: [String: String] = ["MyLambda/MyLambda.swift": "print(\"placeholder\")\n"],
        _ body: (URL) async throws -> Void
    ) async throws {
        let package = FileManager.default.temporaryDirectory.appending(path: "lambda-init-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: package) }

        if let manifest {
            try manifest.write(to: package.appending(path: "Package.swift"), atomically: true, encoding: .utf8)
        }

        for (relativePath, content) in sources {
            let file = package.appending(path: "Sources").appending(path: relativePath)
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try content.write(to: file, atomically: true, encoding: .utf8)
        }

        try await body(package)
    }

    /// Runs the plugin against `package`, the way the SwiftPM plugin invokes the helper.
    @available(LambdaSwift 2.0, *)
    private func runLambdaInit(in package: URL, arguments: [String] = []) async throws {
        try await Initializer().initialize(arguments: ["--dest-dir", package.path] + arguments)
    }

    /// The content of the file at `relativePath` inside `package`.
    private func contents(of package: URL, at relativePath: String) throws -> String {
        try String(contentsOf: package.appending(path: relativePath), encoding: .utf8)
    }
}
