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

@Suite("BuildManifest")
struct BuildManifestTests {

    @available(LambdaSwift 2.0, *)
    @Test("zip factory records the zip path and no image fields")
    func zipFactory() {
        let manifest = BuildManifest.zip(product: "MyLambda", architecture: .arm64, zipPath: "/out/MyLambda.zip")
        #expect(manifest.schemaVersion == BuildManifest.currentSchemaVersion)
        #expect(manifest.product == "MyLambda")
        #expect(manifest.packageType == .zip)
        #expect(manifest.architecture == .arm64)
        #expect(manifest.zipPath == "/out/MyLambda.zip")
        #expect(manifest.containerCLI == nil)
        #expect(manifest.imageTag == nil)
    }

    @available(LambdaSwift 2.0, *)
    @Test("image factory records the tag, CLI, and architecture and no zip path")
    func imageFactory() {
        let manifest = BuildManifest.image(
            product: "MyLambda",
            architecture: .x64,
            containerCLI: "container",
            imageTag: "swift-lambda/MyLambda:latest"
        )
        #expect(manifest.packageType == .image)
        #expect(manifest.architecture == .x64)
        #expect(manifest.containerCLI == "container")
        #expect(manifest.imageTag == "swift-lambda/MyLambda:latest")
        #expect(manifest.zipPath == nil)
    }

    @available(LambdaSwift 2.0, *)
    @Test(
        "write then read round-trips through disk",
        arguments: [
            BuildManifest.zip(product: "Z", architecture: .arm64, zipPath: "/o/Z.zip"),
            BuildManifest.image(
                product: "I",
                architecture: .x64,
                containerCLI: "docker",
                imageTag: "swift-lambda/I:latest"
            ),
        ]
    )
    func roundTrip(manifest: BuildManifest) throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "manifest-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try manifest.write(into: dir)
        let readBack = try #require(try BuildManifest.read(from: dir))
        #expect(readBack == manifest)
    }

    @available(LambdaSwift 2.0, *)
    @Test("read returns nil when no manifest is present (backwards-compatible fallback)")
    func readMissingReturnsNil() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "manifest-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(try BuildManifest.read(from: dir) == nil)
    }
}
