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
