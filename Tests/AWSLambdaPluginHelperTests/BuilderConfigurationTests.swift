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

@Suite("BuilderConfiguration argument parsing")
struct BuilderConfigurationTests {

    // MARK: - Helper

    /// Provides the mandatory arguments required for BuilderConfiguration to parse successfully.
    private func defaultArgs(
        outputPath: String = "/tmp/output",
        products: String = "MyLambda",
        configuration: String = "release"
    ) -> [String] {
        [
            "--package-id", "my-package",
            "--package-display-name", "MyPackage",
            "--package-directory", "/tmp/project",
            "--docker-tool-path", "/usr/local/bin/docker",
            "--zip-tool-path", "/usr/bin/zip",
            "--output-path", outputPath,
            "--products", products,
            "--configuration", configuration,
        ]
    }

    // MARK: - Cross-compile parsing (Requirement 2.7)

    @Test("--cross-compile with valid value 'docker'")
    func crossCompileDocker() throws {
        let args = defaultArgs() + ["--cross-compile", "docker"]
        let config = try BuilderConfiguration(arguments: args)
        #expect(config.crossCompileMethod == .docker)
    }

    @Test("--cross-compile with valid value 'container'")
    func crossCompileContainer() throws {
        let args = defaultArgs() + ["--cross-compile", "container"]
        let config = try BuilderConfiguration(arguments: args)
        #expect(config.crossCompileMethod == .container)
    }

    @Test("--cross-compile with 'swift-static-sdk' throws unsupported error")
    func crossCompileSwiftStaticSdk() throws {
        let args = defaultArgs() + ["--cross-compile", "swift-static-sdk"]
        #expect(throws: (any Error).self) {
            _ = try BuilderConfiguration(arguments: args)
        }
    }

    @Test("--cross-compile with 'custom-sdk' throws unsupported error")
    func crossCompileCustomSdk() throws {
        let args = defaultArgs() + ["--cross-compile", "custom-sdk"]
        #expect(throws: (any Error).self) {
            _ = try BuilderConfiguration(arguments: args)
        }
    }

    @Test("--cross-compile with invalid value throws error")
    func crossCompileInvalidValue() throws {
        let args = defaultArgs() + ["--cross-compile", "invalid-method"]
        #expect(throws: (any Error).self) {
            _ = try BuilderConfiguration(arguments: args)
        }
    }

    @Test("--cross-compile defaults to docker when omitted")
    func crossCompileDefaultsToDocker() throws {
        let args = defaultArgs()
        let config = try BuilderConfiguration(arguments: args)
        #expect(config.crossCompileMethod == .docker)
    }

    // MARK: - No-strip flag (Requirements 2.5, 2.6)

    @Test("--no-strip flag is detected when present")
    func noStripFlagPresent() throws {
        let args = defaultArgs() + ["--no-strip"]
        let config = try BuilderConfiguration(arguments: args)
        #expect(config.noStrip == true)
    }

    @Test("--no-strip flag defaults to false when omitted")
    func noStripFlagAbsent() throws {
        let args = defaultArgs()
        let config = try BuilderConfiguration(arguments: args)
        #expect(config.noStrip == false)
    }

    // MARK: - Output directory deprecated alias (Requirement 7.5)

    @Test("--output-directory deprecated alias maps to outputDirectory")
    func outputDirectoryAlias() throws {
        let args: [String] = [
            "--package-id", "my-package",
            "--package-display-name", "MyPackage",
            "--package-directory", "/tmp/project",
            "--docker-tool-path", "/usr/local/bin/docker",
            "--zip-tool-path", "/usr/bin/zip",
            "--output-directory", "/custom/output/path",
            "--products", "MyLambda",
            "--configuration", "release",
        ]
        let config = try BuilderConfiguration(arguments: args)
        #expect(config.outputDirectory.path().hasSuffix("custom/output/path"))
    }

    @Test("--output-path takes precedence when both are provided")
    func outputPathTakesPrecedence() throws {
        let args: [String] = [
            "--package-id", "my-package",
            "--package-display-name", "MyPackage",
            "--package-directory", "/tmp/project",
            "--docker-tool-path", "/usr/local/bin/docker",
            "--zip-tool-path", "/usr/bin/zip",
            "--output-path", "/primary/path",
            "--output-directory", "/deprecated/path",
            "--products", "MyLambda",
            "--configuration", "release",
        ]
        let config = try BuilderConfiguration(arguments: args)
        #expect(config.outputDirectory.path().hasSuffix("primary/path"))
    }

    // MARK: - Mutual exclusion of --swift-version and --base-docker-image (Requirement 2.17)

    @Test("--swift-version and --base-docker-image together throws error")
    func mutualExclusionSwiftVersionAndBaseImage() throws {
        let args = defaultArgs() + ["--swift-version", "6.0", "--base-docker-image", "swift:6.0-amazonlinux2023"]
        #expect(throws: (any Error).self) {
            _ = try BuilderConfiguration(arguments: args)
        }
    }

    @Test("--swift-version alone is accepted")
    func swiftVersionAlone() throws {
        let args = defaultArgs() + ["--swift-version", "6.0"]
        let config = try BuilderConfiguration(arguments: args)
        #expect(config.baseDockerImage == "swift:6.0-amazonlinux2023")
    }

    @Test("--base-docker-image alone is accepted")
    func baseDockerImageAlone() throws {
        let args = defaultArgs() + ["--base-docker-image", "swift:5.10-amazonlinux2023"]
        let config = try BuilderConfiguration(arguments: args)
        #expect(config.baseDockerImage == "swift:5.10-amazonlinux2023")
    }

    // MARK: - Default base image is amazonlinux2023 (Requirement 6.1)

    @Test("Default base image contains amazonlinux2023")
    func defaultBaseImageIsAL2023() throws {
        let args = defaultArgs()
        let config = try BuilderConfiguration(arguments: args)
        #expect(config.baseDockerImage.contains("amazonlinux2023"))
    }

    @Test("Default base image format without swift-version is swift:amazonlinux2023")
    func defaultBaseImageFormatNoVersion() throws {
        let args = defaultArgs()
        let config = try BuilderConfiguration(arguments: args)
        #expect(config.baseDockerImage == "swift:amazonlinux2023")
    }

    @Test("Base image with --swift-version includes version prefix")
    func baseImageWithSwiftVersion() throws {
        let args = defaultArgs() + ["--swift-version", "6.1"]
        let config = try BuilderConfiguration(arguments: args)
        #expect(config.baseDockerImage == "swift:6.1-amazonlinux2023")
    }

    // MARK: - Explicit AL2 image detection

    @Test("Explicit AL2 image is detected")
    func explicitAL2ImageDetected() throws {
        let args = defaultArgs() + ["--base-docker-image", "swift:5.10-amazonlinux2"]
        let config = try BuilderConfiguration(arguments: args)
        #expect(config.explicitAL2Image == true)
    }

    @Test("AL2023 image is not flagged as explicit AL2")
    func al2023ImageNotFlaggedAsAL2() throws {
        let args = defaultArgs() + ["--base-docker-image", "swift:6.0-amazonlinux2023"]
        let config = try BuilderConfiguration(arguments: args)
        #expect(config.explicitAL2Image == false)
    }

    @Test("Default image (no --base-docker-image) is not flagged as explicit AL2")
    func defaultImageNotFlaggedAsAL2() throws {
        let args = defaultArgs()
        let config = try BuilderConfiguration(arguments: args)
        #expect(config.explicitAL2Image == false)
    }
}
