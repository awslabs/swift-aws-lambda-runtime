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

// MARK: - DockerCLI argv

/// Golden tests pinning the exact argument vector emitted for the Docker CLI. These are kept
/// independent from the Apple `container` tests on purpose: the two CLIs may diverge, and a shared
/// fixture would let a regression in one hide behind the other.
@Suite("DockerCLI argument vectors")
struct DockerCLIArgumentTests {

    @available(LambdaSwift 2.0, *)
    @Test("pull arguments pin the target platform")
    func pullArguments() {
        let cli = DockerCLI()
        #expect(cli.executableName == "docker")
        #expect(
            cli.pullArguments(image: "swift:amazonlinux2023", architecture: .arm64)
                == ["pull", "--platform", "linux/arm64", "swift:amazonlinux2023"]
        )
        #expect(
            cli.pullArguments(image: "swift:amazonlinux2023", architecture: .x64)
                == ["pull", "--platform", "linux/amd64", "swift:amazonlinux2023"]
        )
    }

    @available(LambdaSwift 2.0, *)
    @Test("run arguments without env pin the target platform")
    func runArgumentsNoEnv() {
        let cli = DockerCLI()
        let args = cli.runArguments(
            baseImage: "swift:amazonlinux2023",
            architecture: .arm64,
            workingDirectory: "/workspace",
            mounts: ["/host/pkg:/workspace"],
            env: nil,
            command: "swift build"
        )
        #expect(
            args == [
                "run", "--platform", "linux/arm64", "--rm",
                "-v", "/host/pkg:/workspace",
                "-w", "/workspace",
                "swift:amazonlinux2023",
                "bash", "-cl", "swift build",
            ]
        )
    }

    @available(LambdaSwift 2.0, *)
    @Test("run arguments with sorted env")
    func runArgumentsWithEnv() {
        let cli = DockerCLI()
        let args = cli.runArguments(
            baseImage: "img",
            architecture: .x64,
            workingDirectory: "/w",
            mounts: ["/a:/b", "/c:/d"],
            env: ["ZED": "1", "ABLE": "2"],
            command: "cmd"
        )
        #expect(
            args == [
                "run", "--platform", "linux/amd64", "--rm",
                "-v", "/a:/b",
                "-v", "/c:/d",
                "-e", "ABLE=2",
                "-e", "ZED=1",
                "-w", "/w",
                "img",
                "bash", "-cl", "cmd",
            ]
        )
    }

    @available(LambdaSwift 2.0, *)
    @Test("build image arguments use --platform for arm64")
    func buildImageArgumentsArm64() {
        let cli = DockerCLI()
        let args = cli.buildImageArguments(
            dockerfile: "/ctx/Dockerfile",
            contextDir: "/ctx",
            tag: "swift-lambda/MyLambda:latest",
            architecture: .arm64
        )
        #expect(
            args == [
                "build",
                "--platform", "linux/arm64",
                "-f", "/ctx/Dockerfile",
                "-t", "swift-lambda/MyLambda:latest",
                "/ctx",
            ]
        )
    }

    @available(LambdaSwift 2.0, *)
    @Test("build image arguments use --platform for x64")
    func buildImageArgumentsX64() {
        let cli = DockerCLI()
        let args = cli.buildImageArguments(
            dockerfile: "/ctx/Dockerfile",
            contextDir: "/ctx",
            tag: "t",
            architecture: .x64
        )
        #expect(
            args == [
                "build",
                "--platform", "linux/amd64",
                "-f", "/ctx/Dockerfile",
                "-t", "t",
                "/ctx",
            ]
        )
    }

    @available(LambdaSwift 2.0, *)
    @Test("login arguments read the password from stdin")
    func loginArguments() {
        let cli = DockerCLI()
        #expect(
            cli.loginArguments(registry: "123.dkr.ecr.eu-central-1.amazonaws.com", username: "AWS")
                == ["login", "--username", "AWS", "--password-stdin", "123.dkr.ecr.eu-central-1.amazonaws.com"]
        )
    }

    @available(LambdaSwift 2.0, *)
    @Test("tag and push arguments")
    func tagAndPushArguments() {
        let cli = DockerCLI()
        #expect(
            cli.tagArguments(source: "swift-lambda/MyLambda:latest", target: "repo:latest") == [
                "tag", "swift-lambda/MyLambda:latest", "repo:latest",
            ]
        )
        #expect(cli.pushArguments(tag: "repo:latest") == ["push", "repo:latest"])
    }
}

// MARK: - AppleContainerCLI argv

/// Golden tests pinning the exact argument vector emitted for Apple's `container` CLI. Independent
/// from the Docker tests by design (see ``DockerCLIArgumentTests``). Note the `image pull` verb and
/// the `--memory 4G` reservation that distinguish this CLI from Docker.
@Suite("AppleContainerCLI argument vectors")
struct AppleContainerCLIArgumentTests {

    @available(LambdaSwift 2.0, *)
    @Test("pull arguments use the image subcommand and pin the platform")
    func pullArguments() {
        let cli = AppleContainerCLI()
        #expect(cli.executableName == "container")
        #expect(
            cli.pullArguments(image: "swift:amazonlinux2023", architecture: .arm64)
                == ["image", "pull", "--platform", "linux/arm64", "swift:amazonlinux2023"]
        )
        #expect(
            cli.pullArguments(image: "swift:amazonlinux2023", architecture: .x64)
                == ["image", "pull", "--platform", "linux/amd64", "swift:amazonlinux2023"]
        )
    }

    @available(LambdaSwift 2.0, *)
    @Test("run arguments select the arch, reserve memory, and come before --rm")
    func runArgumentsNoEnv() {
        let cli = AppleContainerCLI()
        let args = cli.runArguments(
            baseImage: "swift:amazonlinux2023",
            architecture: .arm64,
            workingDirectory: "/workspace",
            mounts: ["/host/pkg:/workspace"],
            env: nil,
            command: "swift build"
        )
        #expect(
            args == [
                "run", "--arch", "arm64", "--memory", "4G", "--rm",
                "-v", "/host/pkg:/workspace",
                "-w", "/workspace",
                "swift:amazonlinux2023",
                "bash", "-cl", "swift build",
            ]
        )
    }

    @available(LambdaSwift 2.0, *)
    @Test("run arguments with sorted env")
    func runArgumentsWithEnv() {
        let cli = AppleContainerCLI()
        let args = cli.runArguments(
            baseImage: "img",
            architecture: .x64,
            workingDirectory: "/w",
            mounts: ["/a:/b"],
            env: ["ZED": "1", "ABLE": "2"],
            command: "cmd"
        )
        #expect(
            args == [
                "run", "--arch", "amd64", "--memory", "4G", "--rm",
                "-v", "/a:/b",
                "-e", "ABLE=2",
                "-e", "ZED=1",
                "-w", "/w",
                "img",
                "bash", "-cl", "cmd",
            ]
        )
    }

    @available(LambdaSwift 2.0, *)
    @Test("build image arguments use --arch and an explicit context dir for arm64")
    func buildImageArgumentsArm64() {
        let cli = AppleContainerCLI()
        let args = cli.buildImageArguments(
            dockerfile: "/ctx/Dockerfile",
            contextDir: "/ctx",
            tag: "swift-lambda/MyLambda:latest",
            architecture: .arm64
        )
        #expect(
            args == [
                "build",
                "--arch", "arm64",
                "-f", "/ctx/Dockerfile",
                "-t", "swift-lambda/MyLambda:latest",
                "/ctx",
            ]
        )
    }

    @available(LambdaSwift 2.0, *)
    @Test("build image arguments use --arch for x64")
    func buildImageArgumentsX64() {
        let cli = AppleContainerCLI()
        let args = cli.buildImageArguments(
            dockerfile: "/ctx/Dockerfile",
            contextDir: "/ctx",
            tag: "t",
            architecture: .x64
        )
        #expect(
            args == [
                "build",
                "--arch", "amd64",
                "-f", "/ctx/Dockerfile",
                "-t", "t",
                "/ctx",
            ]
        )
    }

    @available(LambdaSwift 2.0, *)
    @Test("login uses the registry subcommand and reads the password from stdin")
    func loginArguments() {
        let cli = AppleContainerCLI()
        #expect(
            cli.loginArguments(registry: "123.dkr.ecr.eu-central-1.amazonaws.com", username: "AWS")
                == [
                    "registry", "login", "--username", "AWS", "--password-stdin",
                    "123.dkr.ecr.eu-central-1.amazonaws.com",
                ]
        )
    }

    @available(LambdaSwift 2.0, *)
    @Test("tag and push use the image subcommand")
    func tagAndPushArguments() {
        let cli = AppleContainerCLI()
        #expect(
            cli.tagArguments(source: "swift-lambda/MyLambda:latest", target: "repo:latest") == [
                "image", "tag", "swift-lambda/MyLambda:latest", "repo:latest",
            ]
        )
        #expect(cli.pushArguments(tag: "repo:latest") == ["image", "push", "repo:latest"])
    }
}

// MARK: - BuilderConfiguration.makeCrossCompileBackend

@Suite("Cross-compile backend selection")
struct CrossCompileBackendSelectionTests {

    @available(LambdaSwift 2.0, *)
    static func makeConfiguration(method: String) throws -> BuilderConfiguration {
        try BuilderConfiguration(arguments: [
            "--package-id", "test",
            "--package-display-name", "Test",
            "--package-directory", "/tmp/pkg",
            "--cross-compile-tool-path", "/usr/local/bin/docker",
            "--zip-tool-path", "/usr/bin/zip",
            "--output-path", "/tmp",
            "--products", "MyLambda",
            "--configuration", "release",
            "--cross-compile", method,
        ])
    }

    @available(LambdaSwift 2.0, *)
    @Test("docker selects a container backend running the docker CLI")
    func dockerBackend() throws {
        let backend = try Self.makeConfiguration(method: "docker").makeCrossCompileBackend()
        let container = try #require(backend as? ContainerBuildBackend)
        #expect(container.name == "docker")
        #expect(container.cli is DockerCLI)
    }

    @available(LambdaSwift 2.0, *)
    @Test("container selects a container backend running the apple container CLI")
    func containerBackend() throws {
        let backend = try Self.makeConfiguration(method: "container").makeCrossCompileBackend()
        let container = try #require(backend as? ContainerBuildBackend)
        #expect(container.name == "container")
        #expect(container.cli is AppleContainerCLI)
    }

    @available(LambdaSwift 2.0, *)
    @Test("swift-static-sdk selects the Static Linux SDK backend, no container CLI")
    func staticLinuxSDKBackend() throws {
        let config = try Self.makeConfiguration(method: "swift-static-sdk")
        let backend = try config.makeCrossCompileBackend()
        let sdk = try #require(backend as? StaticLinuxSDKBuildBackend)
        #expect(sdk.name == "swift-static-sdk")
        // The plugin forwards the resolved swift path via --cross-compile-tool-path.
        #expect(sdk.swiftToolPath.path == "/usr/local/bin/docker")
    }
}

// MARK: - Static Linux SDK triple mapping

@Suite("BuildArchitecture musl triple")
struct BuildArchitectureMuslTripleTests {

    @available(LambdaSwift 2.0, *)
    @Test("maps each architecture to its Static Linux SDK triple")
    func muslTriples() {
        #expect(BuildArchitecture.arm64.muslTriple == "aarch64-swift-linux-musl")
        #expect(BuildArchitecture.x64.muslTriple == "x86_64-swift-linux-musl")
    }
}
