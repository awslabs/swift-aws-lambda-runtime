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
    @Test("pull arguments")
    func pullArguments() {
        let cli = DockerCLI()
        #expect(cli.executableName == "docker")
        #expect(cli.pullArguments(image: "swift:amazonlinux2023") == ["pull", "swift:amazonlinux2023"])
    }

    @available(LambdaSwift 2.0, *)
    @Test("run arguments without env")
    func runArgumentsNoEnv() {
        let cli = DockerCLI()
        let args = cli.runArguments(
            baseImage: "swift:amazonlinux2023",
            workingDirectory: "/workspace",
            mounts: ["/host/pkg:/workspace"],
            env: nil,
            command: "swift build"
        )
        #expect(
            args == [
                "run", "--rm",
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
            workingDirectory: "/w",
            mounts: ["/a:/b", "/c:/d"],
            env: ["ZED": "1", "ABLE": "2"],
            command: "cmd"
        )
        #expect(
            args == [
                "run", "--rm",
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
}

// MARK: - AppleContainerCLI argv

/// Golden tests pinning the exact argument vector emitted for Apple's `container` CLI. Independent
/// from the Docker tests by design (see ``DockerCLIArgumentTests``). Note the `image pull` verb and
/// the `--memory 4G` reservation that distinguish this CLI from Docker.
@Suite("AppleContainerCLI argument vectors")
struct AppleContainerCLIArgumentTests {

    @available(LambdaSwift 2.0, *)
    @Test("pull arguments use the image subcommand")
    func pullArguments() {
        let cli = AppleContainerCLI()
        #expect(cli.executableName == "container")
        #expect(cli.pullArguments(image: "swift:amazonlinux2023") == ["image", "pull", "swift:amazonlinux2023"])
    }

    @available(LambdaSwift 2.0, *)
    @Test("run arguments reserve memory and come before --rm")
    func runArgumentsNoEnv() {
        let cli = AppleContainerCLI()
        let args = cli.runArguments(
            baseImage: "swift:amazonlinux2023",
            workingDirectory: "/workspace",
            mounts: ["/host/pkg:/workspace"],
            env: nil,
            command: "swift build"
        )
        #expect(
            args == [
                "run", "--memory", "4G", "--rm",
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
            workingDirectory: "/w",
            mounts: ["/a:/b"],
            env: ["ZED": "1", "ABLE": "2"],
            command: "cmd"
        )
        #expect(
            args == [
                "run", "--memory", "4G", "--rm",
                "-v", "/a:/b",
                "-e", "ABLE=2",
                "-e", "ZED=1",
                "-w", "/w",
                "img",
                "bash", "-cl", "cmd",
            ]
        )
    }
}

// MARK: - CrossCompileMethod.makeBackend

@Suite("CrossCompileMethod backend selection")
struct CrossCompileMethodBackendTests {

    @available(LambdaSwift 2.0, *)
    static func makeConfiguration() throws -> BuilderConfiguration {
        try BuilderConfiguration(arguments: [
            "--package-id", "test",
            "--package-display-name", "Test",
            "--package-directory", "/tmp/pkg",
            "--cross-compile-tool-path", "/usr/local/bin/docker",
            "--zip-tool-path", "/usr/bin/zip",
            "--output-path", "/tmp",
            "--products", "MyLambda",
            "--configuration", "release",
        ])
    }

    @available(LambdaSwift 2.0, *)
    @Test("docker selects a container backend running the docker CLI")
    func dockerBackend() throws {
        let backend = try CrossCompileMethod.docker.makeBackend(configuration: Self.makeConfiguration())
        let container = try #require(backend as? ContainerBuildBackend)
        #expect(container.name == "docker")
        #expect(container.cli is DockerCLI)
    }

    @available(LambdaSwift 2.0, *)
    @Test("container selects a container backend running the apple container CLI")
    func containerBackend() throws {
        let backend = try CrossCompileMethod.container.makeBackend(configuration: Self.makeConfiguration())
        let container = try #require(backend as? ContainerBuildBackend)
        #expect(container.name == "container")
        #expect(container.cli is AppleContainerCLI)
    }

    @available(LambdaSwift 2.0, *)
    @Test("unsupported methods throw", arguments: [CrossCompileMethod.swiftStaticSdk, .customSdk])
    func unsupportedThrows(method: CrossCompileMethod) throws {
        let config = try Self.makeConfiguration()
        #expect(throws: BuilderErrors.self) {
            _ = try method.makeBackend(configuration: config)
        }
    }
}
