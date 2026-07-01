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

@Suite("Deployer ECR reference helpers")
struct DeployerECRReferenceTests {

    @available(LambdaSwift 2.0, *)
    @Test("registry host follows the ECR convention")
    func registryHost() {
        #expect(
            Deployer.ecrRegistryHost(accountId: "123456789012", region: "eu-central-1")
                == "123456789012.dkr.ecr.eu-central-1.amazonaws.com"
        )
    }

    @available(LambdaSwift 2.0, *)
    @Test("ECR-qualified image reference combines registry, repo, and tag")
    func ecrImageReference() {
        #expect(
            Deployer.ecrImageReference(
                accountId: "123456789012",
                region: "us-east-1",
                repository: "MyLambda",
                tag: "latest"
            ) == "123456789012.dkr.ecr.us-east-1.amazonaws.com/MyLambda:latest"
        )
    }

    @available(LambdaSwift 2.0, *)
    @Test("repository name defaults to the lowercased function name")
    func repositoryName() {
        // ECR repository names must be lowercase.
        #expect(Deployer.ecrRepositoryName(for: "MyLambda") == "mylambda")
    }

    @available(LambdaSwift 2.0, *)
    @Test("OCI architecture string maps from the deploy architecture")
    func ociArchitecture() {
        #expect(Deployer.ociArchitecture(for: .arm64) == "arm64")
        #expect(Deployer.ociArchitecture(for: .x64) == "amd64")
    }
}

@Suite("Deployer container CLI resolution")
struct DeployerContainerCLIResolutionTests {

    @available(LambdaSwift 2.0, *)
    private func configuration(
        crossCompile: String? = nil,
        toolPaths: [String: String]
    ) throws
        -> DeployerConfiguration
    {
        var args: [String] = []
        if let crossCompile {
            args += ["--cross-compile", crossCompile]
        }
        for (name, path) in toolPaths.sorted(by: { $0.key < $1.key }) {
            args += ["--cross-compile-tool-path", "\(name)=\(path)"]
        }
        return try DeployerConfiguration(arguments: args)
    }

    @available(LambdaSwift 2.0, *)
    private func manifest(containerCLI: String) -> BuildManifest {
        BuildManifest.image(
            product: "MyLambda",
            architecture: .arm64,
            containerCLI: containerCLI,
            imageTag: "swift-lambda/mylambda:latest"
        )
    }

    @available(LambdaSwift 2.0, *)
    @Test("an image built with container selects the container CLI and its path, not docker")
    func manifestContainerSelectsContainer() throws {
        // Regression: the manifest's CLI must drive both the argv flavor and the executable, so a
        // container-built image is never pushed with container-style argv against the docker binary.
        let config = try configuration(toolPaths: [
            "docker": "/usr/local/bin/docker",
            "container": "/usr/local/bin/container",
        ])
        let (cli, toolPath) = try Deployer.resolveContainerCLI(
            configuration: config,
            manifest: manifest(containerCLI: "container")
        )
        #expect(cli is AppleContainerCLI)
        #expect(toolPath.path().contains("/usr/local/bin/container"))
    }

    @available(LambdaSwift 2.0, *)
    @Test("an image built with docker selects the docker CLI and its path")
    func manifestDockerSelectsDocker() throws {
        let config = try configuration(toolPaths: [
            "docker": "/usr/local/bin/docker",
            "container": "/usr/local/bin/container",
        ])
        let (cli, toolPath) = try Deployer.resolveContainerCLI(
            configuration: config,
            manifest: manifest(containerCLI: "docker")
        )
        #expect(cli is DockerCLI)
        #expect(toolPath.path().contains("/usr/local/bin/docker"))
    }

    @available(LambdaSwift 2.0, *)
    @Test("explicit --cross-compile overrides the manifest CLI")
    func explicitCrossCompileOverridesManifest() throws {
        let config = try configuration(
            crossCompile: "docker",
            toolPaths: ["docker": "/usr/local/bin/docker", "container": "/usr/local/bin/container"]
        )
        let (cli, toolPath) = try Deployer.resolveContainerCLI(
            configuration: config,
            manifest: manifest(containerCLI: "container")
        )
        #expect(cli is DockerCLI)
        #expect(toolPath.path().contains("/usr/local/bin/docker"))
    }

    @available(LambdaSwift 2.0, *)
    @Test("a descriptive error is thrown when the required CLI path was not resolved")
    func missingRequiredCLIThrows() throws {
        // Only docker was resolved, but the image was built with container.
        let config = try configuration(toolPaths: ["docker": "/usr/local/bin/docker"])
        #expect {
            _ = try Deployer.resolveContainerCLI(
                configuration: config,
                manifest: manifest(containerCLI: "container")
            )
        } throws: { error in
            guard case DeployerErrors.ecrError(let message) = error else { return false }
            return message.contains("container")
        }
    }
}

@Suite("Deployer ECR image index unwrap")
struct DeployerECRImageIndexUnwrapTests {

    /// A representative OCI image index with two children (arm64 + an attestation entry with
    /// platform.architecture "unknown"), as docker/container push to ECR.
    static let indexJSON = """
        {
          "schemaVersion": 2,
          "mediaType": "application/vnd.oci.image.index.v1+json",
          "manifests": [
            {
              "mediaType": "application/vnd.oci.image.manifest.v1+json",
              "digest": "sha256:aaaa",
              "platform": { "architecture": "arm64", "os": "linux" }
            },
            {
              "mediaType": "application/vnd.oci.image.manifest.v1+json",
              "digest": "sha256:bbbb",
              "platform": { "architecture": "amd64", "os": "linux" }
            },
            {
              "mediaType": "application/vnd.oci.image.manifest.v1+json",
              "digest": "sha256:cccc",
              "platform": { "architecture": "unknown", "os": "unknown" }
            }
          ]
        }
        """

    @available(LambdaSwift 2.0, *)
    @Test("selects the child manifest digest matching the target architecture")
    func selectsByArchitecture() throws {
        #expect(
            try Deployer.childManifestDigest(indexManifestJSON: Self.indexJSON, architecture: .arm64)
                == "sha256:aaaa"
        )
        #expect(
            try Deployer.childManifestDigest(indexManifestJSON: Self.indexJSON, architecture: .x64)
                == "sha256:bbbb"
        )
    }

    @available(LambdaSwift 2.0, *)
    @Test("throws when no child matches the target architecture")
    func throwsWhenNoMatch() {
        let onlyArm = """
            { "manifests": [ { "digest": "sha256:aaaa", "platform": { "architecture": "arm64" } } ] }
            """
        #expect(throws: DeployerErrors.self) {
            _ = try Deployer.childManifestDigest(indexManifestJSON: onlyArm, architecture: .x64)
        }
    }

    @available(LambdaSwift 2.0, *)
    @Test("throws notAnIndex for a flat manifest with no manifests array")
    func flatManifestThrowsNotAnIndex() {
        let flat = """
            { "schemaVersion": 2, "mediaType": "application/vnd.docker.distribution.manifest.v2+json", "config": {} }
            """
        #expect {
            _ = try Deployer.childManifestDigest(indexManifestJSON: flat, architecture: .arm64)
        } throws: { error in
            guard case DeployerErrors.imageManifestNotAnIndex = error else { return false }
            return true
        }
    }
}
