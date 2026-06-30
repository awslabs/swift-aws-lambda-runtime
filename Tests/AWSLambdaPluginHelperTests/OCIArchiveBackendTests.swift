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

@Suite("OCIArchiveBackend")
struct OCIArchiveBackendTests {

    @available(LambdaSwift 2.0, *)
    static func makeBackend(baseImage: String = OCIArchiveBackend.defaultBaseImage) -> OCIArchiveBackend {
        OCIArchiveBackend(
            cli: DockerCLI(),
            toolPath: URL(fileURLWithPath: "/usr/local/bin/docker"),
            architecture: .arm64,
            baseImage: baseImage
        )
    }

    @available(LambdaSwift 2.0, *)
    @Test("name is oci")
    func name() {
        #expect(Self.makeBackend().name == "oci")
    }

    @available(LambdaSwift 2.0, *)
    @Test("image tag follows the swift-lambda/<product>:latest convention, lowercased")
    func imageTag() {
        // OCI/Docker image references must be lowercase, so the product name is lowercased.
        #expect(OCIArchiveBackend.imageTag(for: "MyLambda") == "swift-lambda/mylambda:latest")
    }

    @available(LambdaSwift 2.0, *)
    @Test("Dockerfile without resources is the minimal AL2023 / bootstrap entrypoint form")
    func dockerfileWithoutResources() {
        let dockerfile = Self.makeBackend().dockerfileContents(resourceDirectoryNames: [])
        #expect(
            dockerfile == """
                FROM public.ecr.aws/amazonlinux/amazonlinux:2023-minimal
                COPY bootstrap /var/runtime/bootstrap
                ENTRYPOINT ["/var/runtime/bootstrap"]

                """
        )
    }

    @available(LambdaSwift 2.0, *)
    @Test("Dockerfile copies resources bundles, sorted and before the entrypoint")
    func dockerfileWithResources() {
        let dockerfile = Self.makeBackend().dockerfileContents(
            resourceDirectoryNames: ["MyLambda_MyLambda.resources", "Another_Pkg.resources"]
        )
        #expect(
            dockerfile == """
                FROM public.ecr.aws/amazonlinux/amazonlinux:2023-minimal
                COPY bootstrap /var/runtime/bootstrap
                COPY Another_Pkg.resources /var/runtime/Another_Pkg.resources
                COPY MyLambda_MyLambda.resources /var/runtime/MyLambda_MyLambda.resources
                ENTRYPOINT ["/var/runtime/bootstrap"]

                """
        )
    }

    @available(LambdaSwift 2.0, *)
    @Test("a custom --base-oci-image flows into the Dockerfile FROM line")
    func dockerfileWithCustomBaseImage() {
        let dockerfile = Self.makeBackend(baseImage: "public.ecr.aws/lambda/provided:al2023")
            .dockerfileContents(resourceDirectoryNames: [])
        #expect(
            dockerfile == """
                FROM public.ecr.aws/lambda/provided:al2023
                COPY bootstrap /var/runtime/bootstrap
                ENTRYPOINT ["/var/runtime/bootstrap"]

                """
        )
    }

    @available(LambdaSwift 2.0, *)
    @Test("archive lays out the build context (bootstrap + Dockerfile) and returns an .ociImage")
    func archiveLaysOutContext() throws {
        // A real build shells out to docker/container, which the test environment may not have. We
        // exercise everything up to that point: the context directory, the relocated binary, and the
        // generated Dockerfile. The CLI invocation fails fast (bogus tool path) and we assert on the
        // artifacts written to disk before that point.
        let root = FileManager.default.temporaryDirectory
            .appending(path: "ociarchive-test-\(UUID().uuidString)")
        let buildDir = root.appending(path: "build")
        let outputDir = root.appending(path: "out")
        try FileManager.default.createDirectory(at: buildDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let product = "MyLambda"
        let binary = buildDir.appending(path: product)
        try Data("#!/bin/sh\necho hi\n".utf8).write(to: binary)

        let backend = OCIArchiveBackend(
            cli: DockerCLI(),
            toolPath: URL(fileURLWithPath: "/nonexistent/docker-\(UUID().uuidString)"),
            architecture: .arm64,
            baseImage: OCIArchiveBackend.defaultBaseImage
        )

        // The build step is expected to fail (no real CLI), but the context must be laid out first.
        #expect(throws: (any Error).self) {
            _ = try backend.archive(
                products: [product: binary],
                outputDirectory: outputDir,
                verboseLogging: false
            )
        }

        let contextDir = outputDir.appending(path: product)
        let bootstrap = contextDir.appending(path: "bootstrap")
        let dockerfile = contextDir.appending(path: "Dockerfile")
        #expect(FileManager.default.fileExists(atPath: bootstrap.path()))
        #expect(FileManager.default.fileExists(atPath: dockerfile.path()))

        let contents = try String(decoding: Data(contentsOf: dockerfile), as: UTF8.self)
        #expect(contents.contains("FROM public.ecr.aws/amazonlinux/amazonlinux:2023-minimal"))
        #expect(contents.contains("ENTRYPOINT [\"/var/runtime/bootstrap\"]"))
    }
}
