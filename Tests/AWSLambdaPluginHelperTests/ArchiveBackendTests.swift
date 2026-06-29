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

@Suite("ArchiveFormat parsing")
struct ArchiveFormatTests {

    @available(LambdaSwift 2.0, *)
    @Test("nil defaults to zip")
    func defaultsToZip() throws {
        #expect(try ArchiveFormat.parse(nil) == .zip)
    }

    @available(LambdaSwift 2.0, *)
    @Test("zip parses and is case-insensitive", arguments: ["zip", "ZIP", "Zip"])
    func parsesZip(value: String) throws {
        #expect(try ArchiveFormat.parse(value) == .zip)
    }

    @available(LambdaSwift 2.0, *)
    @Test("oci is recognised but not yet supported")
    func ociUnsupported() {
        #expect(throws: BuilderErrors.self) {
            _ = try ArchiveFormat.parse("oci")
        }
    }

    @available(LambdaSwift 2.0, *)
    @Test("unknown values throw")
    func unknownThrows() {
        #expect(throws: BuilderErrors.self) {
            _ = try ArchiveFormat.parse("tarball")
        }
    }
}

@Suite("Archive backend selection")
struct ArchiveBackendSelectionTests {

    @available(LambdaSwift 2.0, *)
    @Test("zip selects the ZipArchiveBackend")
    func zipSelectsZipBackend() throws {
        let configuration = try BuilderConfiguration(arguments: [
            "--package-id", "test",
            "--package-display-name", "Test",
            "--package-directory", "/tmp/pkg",
            "--cross-compile-tool-path", "/usr/local/bin/docker",
            "--zip-tool-path", "/usr/bin/zip",
            "--output-path", "/tmp",
            "--products", "MyLambda",
            "--configuration", "release",
            "--archive-format", "zip",
        ])
        let backend = try configuration.makeArchiveBackend()
        let zip = try #require(backend as? ZipArchiveBackend)
        #expect(zip.name == "zip")
    }
}

@Suite("ZipArchiveBackend")
struct ZipArchiveBackendTests {

    @available(LambdaSwift 2.0, *)
    @Test("name is zip")
    func name() {
        #expect(ZipArchiveBackend(zipToolPath: URL(fileURLWithPath: "/usr/bin/zip")).name == "zip")
    }

    @available(LambdaSwift 2.0, *)
    @Test("archive produces a <product>.zip per built product")
    func archiveProducesZip() throws {
        // Lay out a fake build output: <tmp>/build/<product> executable, and a separate output dir.
        let root = FileManager.default.temporaryDirectory
            .appending(path: "ziparchive-test-\(UUID().uuidString)")
        let buildDir = root.appending(path: "build")
        let outputDir = root.appending(path: "out")
        try FileManager.default.createDirectory(at: buildDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let product = "MyLambda"
        let binary = buildDir.appending(path: product)
        try Data("#!/bin/sh\necho hi\n".utf8).write(to: binary)

        let backend = ZipArchiveBackend(zipToolPath: URL(fileURLWithPath: "/usr/bin/zip"))
        let archives = try backend.archive(
            products: [product: binary],
            outputDirectory: outputDir,
            verboseLogging: false
        )

        let zipURL = try #require(archives[product])
        #expect(zipURL.lastPathComponent == "\(product).zip")
        #expect(FileManager.default.fileExists(atPath: zipURL.path()))

        // The binary is relocated to "bootstrap" next to the zip, as the Lambda runtime expects.
        let bootstrap = outputDir.appending(path: product).appending(path: "bootstrap")
        #expect(FileManager.default.fileExists(atPath: bootstrap.path()))
    }
}
