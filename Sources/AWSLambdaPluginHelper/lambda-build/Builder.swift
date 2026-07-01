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

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@available(LambdaSwift 2.0, *)
struct Builder {
    func build(arguments: [String]) async throws {
        let configuration = try BuilderConfiguration(arguments: arguments)

        if configuration.help {
            self.displayHelpMessage()
            return
        }

        // display informational warning only when user explicitly selects an AL2 image
        if configuration.explicitAL2Image {
            self.displayAL2Warning()
        }

        // Select the build backend: build natively when already on an Amazon Linux host,
        // otherwise cross-compile using the backend chosen by --cross-compile.
        let backend: any BuildBackend
        if self.isAmazonLinux(.al2) || self.isAmazonLinux(.al2023) {
            // A native build compiles for the host architecture only; it cannot target another one.
            // Recording a mismatched architecture in the manifest would recreate the very bug the
            // --architecture flag exists to prevent, so reject an explicit cross-architecture request.
            guard configuration.architecture == .host else {
                throw BuilderErrors.invalidArgument(
                    "cannot build for '\(configuration.architecture)' on a '\(BuildArchitecture.host)' "
                        + "Amazon Linux host: a native build targets the host architecture only. "
                        + "Build on a '\(configuration.architecture)' host, or cross-compile from a non-Amazon "
                        + "Linux host (docker or container)."
                )
            }
            backend = NativeBuildBackend()
        } else {
            backend = try configuration.makeCrossCompileBackend()
        }

        let builtProducts = try backend.build(
            packageIdentity: configuration.packageID,
            packageDirectory: configuration.packageDirectory,
            products: configuration.products,
            buildConfiguration: configuration.buildConfiguration,
            noStrip: configuration.noStrip,
            verboseLogging: configuration.verboseLogging
        )

        // Package the built binaries into deployable artifacts, in the format chosen by
        // --archive-format (ZIP today; OCI is stubbed for the future).
        let archiveBackend = try configuration.makeArchiveBackend()
        let archives = try archiveBackend.archive(
            products: builtProducts,
            outputDirectory: configuration.outputDirectory,
            verboseLogging: configuration.verboseLogging
        )

        print(
            "\(archives.count > 0 ? archives.count.description : "no") archive\(archives.count != 1 ? "s" : "") created"
        )
        for (product, artifact) in archives {
            print("  * \(product) at \(artifact)")
        }
    }

    private enum AmazonLinuxVersion {
        case al2
        case al2023
    }

    private func isAmazonLinux(_ version: AmazonLinuxVersion) -> Bool {
        guard let data = FileManager.default.contents(atPath: "/etc/system-release"),
            let release = String(data: data, encoding: .utf8)
        else {
            return false
        }
        switch version {
        case .al2023:
            return release.hasPrefix("Amazon Linux release 2023")
        case .al2:
            return release.hasPrefix("Amazon Linux release 2")
                && !release.hasPrefix("Amazon Linux release 2023")
        }
    }

    private func displayAL2Warning() {
        let yellow = "\u{001b}[33m"
        let reset = "\u{001b}[0m"
        print(
            "\(yellow)warning: Amazon Linux 2 is deprecated. "
                + "Consider migrating to Amazon Linux 2023 (--base-docker-image swift:<version>-amazonlinux2023).\(reset)"
        )
    }

    private func displayHelpMessage() {
        print(
            """
            OVERVIEW: A SwiftPM plugin to build and package your lambda function.

            REQUIREMENTS: To use this plugin, you must have docker or container installed and started.

            USAGE: swift package --allow-network-connections docker lambda-build
                                                       [--help] [--verbose]
                                                       [--output-path <path>]
                                                       [--products <list of products>]
                                                       [--configuration debug | release]
                                                       [--swift-version <version>]
                                                       [--base-docker-image <docker_image_name>]
                                                       [--disable-docker-image-update]
                                                       [--cross-compile <docker | container | swift-static-sdk | custom-sdk>]
                                                       [--archive-format <zip | oci>]
                                                       [--architecture <x64 | arm64>]
                                                       [--base-oci-image <oci_image_name>]
                                                       [--no-strip]


            OPTIONS:
            --verbose                     Produce verbose output for debugging.
            --output-path <path>          The path of the binary package.
                                          (default is `.build/plugins/AWSLambdaBuilder/outputs/...`)
            --products <list>             The list of executable targets to build.
                                          (default is taken from Package.swift)
            --configuration <name>        The build configuration (debug or release)
                                          (default is release)
            --swift-version               The swift version to use for building.
                                          (default is latest)
                                          This parameter cannot be used when --base-docker-image is specified.
            --base-docker-image <name>    The name of the base docker image to use for the build.
                                          (default: swift:<version>-amazonlinux2023)
                                          Amazon Linux 2 is deprecated since June 30, 2026.
                                          Visit Docker Hub for all available swift tags:
                                          https://hub.docker.com/_/swift/tags?name=amazonlinux
                                          This parameter cannot be used when --swift-version is specified.
            --disable-docker-image-update Do not attempt to update the docker image.
            --cross-compile <method>      The cross-compilation method to use.
                                          Values: docker, container, swift-static-sdk, custom-sdk
                                          (default is docker)
                                          Note: swift-static-sdk and custom-sdk are not yet supported.
            --archive-format <format>     The packaging format for the build artifact.
                                          Values: zip, oci
                                          (default is zip)
                                          oci builds an OCI image (deploy support: see lambda-deploy).
            --architecture <arch>         The CPU architecture to build for.
                                          Values: x64, arm64
                                          (default: host architecture)
                                          Recorded in the build manifest; lambda-deploy deploys the
                                          function for this architecture.
            --base-oci-image <name>       The base image for the OCI image (--archive-format oci).
                                          (default: public.ecr.aws/amazonlinux/amazonlinux:2023-minimal)
                                          Use a glibc-compatible Amazon Linux 2023 base.
            --no-strip                    Do not strip debug symbols from the binary.
            --help                        Show help information.
            """
        )
    }
}

@available(LambdaSwift 2.0, *)
struct BuilderConfiguration: CustomStringConvertible {

    // passed by the user
    public let help: Bool
    public let outputDirectory: URL
    public let products: [String]
    public let buildConfiguration: BuildConfiguration
    public let verboseLogging: Bool
    public let baseDockerImage: String
    public let disableDockerImageUpdate: Bool
    public let crossCompileMethod: CrossCompileMethod
    public let archiveFormat: ArchiveFormat
    public let architecture: BuildArchitecture
    public let baseOCIImage: String
    public let noStrip: Bool
    public let explicitAL2Image: Bool

    // passed by the plugin
    public let packageID: String
    public let packageDisplayName: String
    public let packageDirectory: URL
    public let crossCompileToolPath: URL
    public let zipToolPath: URL

    public init(arguments: [String]) throws {
        var argumentExtractor = ArgumentExtractor(arguments)

        let verboseArgument = argumentExtractor.extractFlag(named: "verbose") > 0
        let outputPathArgument = argumentExtractor.extractOption(named: "output-path")
        let outputDirectoryArgument = argumentExtractor.extractOption(named: "output-directory")
        let packageIDArgument = argumentExtractor.extractOption(named: "package-id")
        let packageDisplayNameArgument = argumentExtractor.extractOption(named: "package-display-name")
        let packageDirectoryArgument = argumentExtractor.extractOption(named: "package-directory")
        let crossCompileToolPathArgument = argumentExtractor.extractOption(named: "cross-compile-tool-path")
        let zipToolPathArgument = argumentExtractor.extractOption(named: "zip-tool-path")
        let productsArgument = argumentExtractor.extractOption(named: "products")
        let configurationArgument = argumentExtractor.extractOption(named: "configuration")
        let swiftVersionArgument = argumentExtractor.extractOption(named: "swift-version")
        let baseDockerImageArgument = argumentExtractor.extractOption(named: "base-docker-image")
        let disableDockerImageUpdateArgument = argumentExtractor.extractFlag(named: "disable-docker-image-update") > 0
        let crossCompileArgument = argumentExtractor.extractOption(named: "cross-compile")
        let archiveFormatArgument = argumentExtractor.extractOption(named: "archive-format")
        let architectureArgument = argumentExtractor.extractOption(named: "architecture")
        let baseOCIImageArgument = argumentExtractor.extractOption(named: "base-oci-image")
        let noStripArgument = argumentExtractor.extractFlag(named: "no-strip") > 0
        let helpArgument = argumentExtractor.extractFlag(named: "help") > 0

        // help required ?
        self.help = helpArgument

        // verbose logging required ?
        self.verboseLogging = verboseArgument

        // package id
        guard !packageIDArgument.isEmpty else {
            throw BuilderErrors.invalidArgument("--package-id argument is required")
        }
        self.packageID = packageIDArgument.first!

        // package display name
        guard !packageDisplayNameArgument.isEmpty else {
            throw BuilderErrors.invalidArgument("--package-display-name argument is required")
        }
        self.packageDisplayName = packageDisplayNameArgument.first!

        // package directory
        guard !packageDirectoryArgument.isEmpty else {
            throw BuilderErrors.invalidArgument("--package-directory argument is required")
        }
        self.packageDirectory = URL(fileURLWithPath: packageDirectoryArgument.first!)

        // cross-compile tool path
        guard !crossCompileToolPathArgument.isEmpty else {
            throw BuilderErrors.invalidArgument("--cross-compile-tool-path argument is required")
        }
        self.crossCompileToolPath = URL(fileURLWithPath: crossCompileToolPathArgument.first!)

        // zip tool path
        guard !zipToolPathArgument.isEmpty else {
            throw BuilderErrors.invalidArgument("--zip-tool-path argument is required")
        }
        self.zipToolPath = URL(fileURLWithPath: zipToolPathArgument.first!)

        // output directory
        // --output-directory is a deprecated alias for --output-path (backward compatibility)
        let resolvedOutputPath: String
        if let outputPath = outputPathArgument.first {
            resolvedOutputPath = outputPath
        } else if let outputDirectory = outputDirectoryArgument.first {
            print("warning: '--output-directory' is deprecated, use '--output-path' instead.")
            resolvedOutputPath = outputDirectory
        } else {
            throw BuilderErrors.invalidArgument("--output-path is required")
        }
        self.outputDirectory = URL(fileURLWithPath: resolvedOutputPath)

        // products
        guard !productsArgument.isEmpty else {
            throw BuilderErrors.invalidArgument("--products argument is required")
        }
        self.products = productsArgument.flatMap { $0.split(separator: ",").map(String.init) }

        // build configuration
        guard let buildConfigurationName = configurationArgument.first else {
            throw BuilderErrors.invalidArgument("--configuration argument is required")
        }
        guard let _buildConfiguration = BuildConfiguration(rawValue: buildConfigurationName) else {
            throw BuilderErrors.invalidArgument("invalid build configuration named '\(buildConfigurationName)'")
        }
        self.buildConfiguration = _buildConfiguration

        guard !(!swiftVersionArgument.isEmpty && !baseDockerImageArgument.isEmpty) else {
            throw BuilderErrors.invalidArgument("--swift-version and --base-docker-image are mutually exclusive")
        }

        let swiftVersion = swiftVersionArgument.first ?? .none  // undefined version will yield the latest docker image

        self.baseDockerImage =
            baseDockerImageArgument.first ?? "swift:\(swiftVersion.map { $0 + "-" } ?? "")amazonlinux2023"

        self.disableDockerImageUpdate = disableDockerImageUpdateArgument
        self.crossCompileMethod = try CrossCompileMethod.parse(crossCompileArgument.first)
        self.archiveFormat = try ArchiveFormat.parse(archiveFormatArgument.first)
        self.architecture = try BuildArchitecture.parse(architectureArgument.first)

        // --base-oci-image only applies to the OCI image build; reject it for other formats rather
        // than silently ignoring it.
        guard baseOCIImageArgument.isEmpty || self.archiveFormat == .oci else {
            throw BuilderErrors.invalidArgument("--base-oci-image can only be used with --archive-format oci")
        }
        self.baseOCIImage = baseOCIImageArgument.first ?? OCIArchiveBackend.defaultBaseImage
        self.noStrip = noStripArgument

        // detect when user explicitly provides an AL2 (not AL2023) base image
        if let explicitImage = baseDockerImageArgument.first {
            self.explicitAL2Image =
                explicitImage.contains("amazonlinux2")
                && !explicitImage.contains("amazonlinux2023")
        } else {
            self.explicitAL2Image = false
        }

        if self.verboseLogging {
            print("-------------------------------------------------------------------------")
            print("configuration")
            print("-------------------------------------------------------------------------")
            print(self)
        }
    }

    /// Creates the ``BuildBackend`` that performs a cross-compiled build for the configured method.
    ///
    /// Used when the host is not already an Amazon Linux machine. The configuration already holds
    /// everything a backend needs (the resolved tool path, base image, and image-update
    /// preference), so the factory lives here rather than on ``CrossCompileMethod``.
    func makeCrossCompileBackend() throws -> any BuildBackend {
        let cli = try self.makeContainerCLI()
        return ContainerBuildBackend(
            cli: cli,
            toolPath: self.crossCompileToolPath,
            baseImage: self.baseDockerImage,
            disableImageUpdate: self.disableDockerImageUpdate,
            architecture: self.architecture,
            method: self.crossCompileMethod
        )
    }

    /// Resolves the ``ContainerCLI`` argument flavor for the configured cross-compile method.
    ///
    /// Shared by the build backend and the OCI archive backend — both shell out through the same
    /// container CLI (docker or Apple's `container`).
    private func makeContainerCLI() throws -> any ContainerCLI {
        switch self.crossCompileMethod {
        case .docker:
            return DockerCLI()
        case .container:
            return AppleContainerCLI()
        case .swiftStaticSdk, .customSdk:
            throw BuilderErrors.unsupportedCrossCompileMethod(self.crossCompileMethod)
        }
    }

    /// Creates the ``ArchiveBackend`` that packages the built binaries for the configured format.
    func makeArchiveBackend() throws -> any ArchiveBackend {
        switch self.archiveFormat {
        case .zip:
            return ZipArchiveBackend(zipToolPath: self.zipToolPath, architecture: self.architecture)
        case .oci:
            // An OCI image bakes in a single architecture: the one selected by --architecture.
            return OCIArchiveBackend(
                cli: try self.makeContainerCLI(),
                toolPath: self.crossCompileToolPath,
                architecture: self.architecture,
                baseImage: self.baseOCIImage
            )
        }
    }

    var description: String {
        """
        {
          outputDirectory: \(self.outputDirectory)
          products: \(self.products)
          buildConfiguration: \(self.buildConfiguration)
          crossCompileToolPath: \(self.crossCompileToolPath)
          baseDockerImage: \(self.baseDockerImage)
          disableDockerImageUpdate: \(self.disableDockerImageUpdate)
          crossCompileMethod: \(self.crossCompileMethod)
          archiveFormat: \(self.archiveFormat)
          architecture: \(self.architecture)
          baseOCIImage: \(self.baseOCIImage)
          zipToolPath: \(self.zipToolPath)
          packageID: \(self.packageID)
          packageDisplayName: \(self.packageDisplayName)
          packageDirectory: \(self.packageDirectory)
        }
        """
    }
}

@available(LambdaSwift 2.0, *)
enum BuilderErrors: Error, CustomStringConvertible {
    case invalidArgument(String)
    case unsupportedPlatform(String)
    case unknownProduct(String)
    case productExecutableNotFound(String)
    case unsupportedCrossCompileMethod(CrossCompileMethod)
    case unsupportedArchiveFormat(ArchiveFormat)
    case containerCLINotFound(CrossCompileMethod)
    case failedWritingDockerfile
    case failedParsingDockerOutput(String)
    case processFailed([String], Int32)

    var description: String {
        switch self {
        case .invalidArgument(let description):
            return description
        case .unsupportedPlatform(let description):
            return description
        case .unknownProduct(let description):
            return description
        case .productExecutableNotFound(let product):
            return "product executable not found '\(product)'"
        case .unsupportedCrossCompileMethod(let method):
            return
                "The '\(method)' cross-compilation method is not yet supported. "
                + "For information on how to install and use Swift cross-compilation SDKs, visit: "
                + "https://www.swift.org/documentation/articles/static-linux-getting-started.html"
        case .unsupportedArchiveFormat(let format):
            return "The '\(format)' archive format is not yet supported."
        case .containerCLINotFound(let method):
            switch method {
            case .docker:
                return
                    "Docker is not installed or not found at the expected path. "
                    + "Install Docker from https://docs.docker.com/get-docker/"
            case .container:
                return
                    "Apple's 'container' CLI is not installed or not found at the expected path. "
                    + "Install it from https://github.com/apple/container"
            case .swiftStaticSdk, .customSdk:
                return
                    "The '\(method)' cross-compilation method is not yet supported. "
                    + "For information on how to install and use Swift cross-compilation SDKs, visit: "
                    + "https://www.swift.org/documentation/articles/static-linux-getting-started.html"
            }
        case .failedWritingDockerfile:
            return "failed writing dockerfile"
        case .failedParsingDockerOutput(let output):
            return "failed parsing docker output: '\(output)'"
        case .processFailed(let arguments, let code):
            return "\(arguments.joined(separator: " ")) failed with code \(code)"
        }
    }
}

@available(LambdaSwift 2.0, *)
enum BuildConfiguration: String {
    case debug
    case release
}
