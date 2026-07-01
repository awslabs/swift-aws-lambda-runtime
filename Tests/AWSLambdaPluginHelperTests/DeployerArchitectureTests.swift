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

/// Covers the build→deploy architecture hand-off (issue #683): the deploy step must deploy the
/// function for the architecture the artifact was actually built for, and reject an explicit
/// `--architecture` that disagrees with it.
@Suite("Deployer architecture reconciliation")
struct DeployerArchitectureTests {

    @available(LambdaSwift 2.0, *)
    private func configuration(architecture: String? = nil) throws -> DeployerConfiguration {
        try DeployerConfiguration(arguments: architecture.map { ["--architecture", $0] } ?? [])
    }

    @available(LambdaSwift 2.0, *)
    @Test("no manifest falls back to the configured architecture")
    func noManifestUsesConfigured() throws {
        let config = try configuration(architecture: "arm64")
        let resolved = try Deployer.reconcileArchitecture(
            configuration: config,
            manifest: nil,
            functionName: "MyLambda"
        )
        #expect(resolved == .arm64)
    }

    @available(LambdaSwift 2.0, *)
    @Test("no manifest and no explicit architecture uses the host")
    func noManifestNoExplicitUsesHost() throws {
        let config = try configuration()
        let resolved = try Deployer.reconcileArchitecture(
            configuration: config,
            manifest: nil,
            functionName: "MyLambda"
        )
        #expect(resolved == .host)
    }

    @available(LambdaSwift 2.0, *)
    @Test("omitted --architecture adopts the built architecture from the manifest")
    func omittedAdoptsBuiltArchitecture() throws {
        let config = try configuration()
        let manifest = BuildManifest.zip(product: "MyLambda", architecture: .arm64, zipPath: "/o/MyLambda.zip")
        let resolved = try Deployer.reconcileArchitecture(
            configuration: config,
            manifest: manifest,
            functionName: "MyLambda"
        )
        // Regardless of the host, the built architecture wins when the flag is omitted.
        #expect(resolved == .arm64)
    }

    @available(LambdaSwift 2.0, *)
    @Test("explicit --architecture matching the built architecture is accepted")
    func explicitMatchingIsAccepted() throws {
        let config = try configuration(architecture: "x64")
        let manifest = BuildManifest.image(
            product: "MyLambda",
            architecture: .x64,
            containerCLI: "docker",
            imageTag: "swift-lambda/mylambda:latest"
        )
        let resolved = try Deployer.reconcileArchitecture(
            configuration: config,
            manifest: manifest,
            functionName: "MyLambda"
        )
        #expect(resolved == .x64)
    }

    @available(LambdaSwift 2.0, *)
    @Test("explicit --architecture disagreeing with the built artifact is a hard error")
    func explicitMismatchThrows() throws {
        let config = try configuration(architecture: "x64")
        let manifest = BuildManifest.zip(product: "MyLambda", architecture: .arm64, zipPath: "/o/MyLambda.zip")
        #expect(throws: DeployerErrors.self) {
            _ = try Deployer.reconcileArchitecture(
                configuration: config,
                manifest: manifest,
                functionName: "MyLambda"
            )
        }
    }

    @available(LambdaSwift 2.0, *)
    @Test("the mismatch error names the function and both architectures")
    func mismatchErrorIsDescriptive() throws {
        let config = try configuration(architecture: "x64")
        let manifest = BuildManifest.zip(product: "MyLambda", architecture: .arm64, zipPath: "/o/MyLambda.zip")
        do {
            _ = try Deployer.reconcileArchitecture(
                configuration: config,
                manifest: manifest,
                functionName: "MyLambda"
            )
            Issue.record("expected an architecture mismatch error")
        } catch let error as DeployerErrors {
            let description = error.description
            #expect(description.contains("MyLambda"))
            #expect(description.contains("x64"))
            #expect(description.contains("arm64"))
        }
    }
}
