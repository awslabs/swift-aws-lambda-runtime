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

        let builtProducts: [String: URL]

        if self.isAmazonLinux(.al2) || self.isAmazonLinux(.al2023) {
            // native build on Amazon Linux
            builtProducts = try self.buildNative(
                packageIdentity: configuration.packageID,
                products: configuration.products,
                buildConfiguration: configuration.buildConfiguration,
                noStrip: configuration.noStrip,
                verboseLogging: configuration.verboseLogging
            )
        } else {
            // build with docker/container
            builtProducts = try self.buildInDocker(
                packageIdentity: configuration.packageID,
                packageDirectory: configuration.packageDirectory,
                products: configuration.products,
                containerCLIPath: configuration.dockerToolPath,
                containerCLI: configuration.crossCompileMethod,
                outputDirectory: configuration.outputDirectory,
                baseImage: configuration.baseDockerImage,
                disableDockerImageUpdate: configuration.disableDockerImageUpdate,
                buildConfiguration: configuration.buildConfiguration,
                noStrip: configuration.noStrip,
                verboseLogging: configuration.verboseLogging
            )
        }

        // create the archive
        let archives = try self.package(
            packageName: configuration.packageDisplayName,
            products: builtProducts,
            zipToolPath: configuration.zipToolPath,
            outputDirectory: configuration.outputDirectory,
            verboseLogging: configuration.verboseLogging
        )

        print(
            "\(archives.count > 0 ? archives.count.description : "no") archive\(archives.count != 1 ? "s" : "") created"
        )
        for (product, archivePath) in archives {
            print("  * \(product) at \(archivePath.path())")
        }
    }

    private func buildNative(
        packageIdentity: String,
        products: [String],
        buildConfiguration: BuildConfiguration,
        noStrip: Bool,
        verboseLogging: Bool
    ) throws -> [String: URL] {
        print("-------------------------------------------------------------------------")
        print("building \"\(packageIdentity)\"")
        print("-------------------------------------------------------------------------")

        var results = [String: URL]()
        for product in products {
            print("building \"\(product)\"")
            var buildArguments = [
                "build", "-c", buildConfiguration.rawValue,
                "--product", product,
                "--static-swift-stdlib",
            ]
            if !noStrip {
                buildArguments += ["-Xlinker", "-s"]
            }
            try Utils.execute(
                executable: URL(fileURLWithPath: "/usr/bin/swift"),
                arguments: buildArguments,
                logLevel: verboseLogging ? .debug : .output
            )

            // get the build output path
            let showBinPathArguments = ["build", "-c", buildConfiguration.rawValue, "--show-bin-path"]
            let binPath = try Utils.execute(
                executable: URL(fileURLWithPath: "/usr/bin/swift"),
                arguments: showBinPathArguments,
                logLevel: .silent
            ).trimmingCharacters(in: .whitespacesAndNewlines)

            let productPath = URL(fileURLWithPath: binPath).appending(path: product)
            guard FileManager.default.fileExists(atPath: productPath.path()) else {
                print("expected '\(product)' binary at \"\(productPath.path())\"")
                throw BuilderErrors.productExecutableNotFound(product)
            }
            results[product] = productPath
        }
        return results
    }

    private func buildInDocker(
        packageIdentity: String,
        packageDirectory: URL,
        products: [String],
        containerCLIPath: URL,
        containerCLI: CrossCompileMethod,
        outputDirectory: URL,
        baseImage: String,
        disableDockerImageUpdate: Bool,
        buildConfiguration: BuildConfiguration,
        noStrip: Bool,
        verboseLogging: Bool
    ) throws -> [String: URL] {

        // verify the container CLI binary exists at the resolved path
        guard FileManager.default.fileExists(atPath: containerCLIPath.path()) else {
            throw BuilderErrors.containerCLINotFound(containerCLI)
        }

        print("-------------------------------------------------------------------------")
        print("building \"\(packageIdentity)\" in \(containerCLI)")
        print("-------------------------------------------------------------------------")

        if !disableDockerImageUpdate {
            // update the underlying image, if necessary
            print("updating \"\(baseImage)\" image")
            try Utils.execute(
                executable: containerCLIPath,
                arguments: containerCLI.pullArguments(image: baseImage),
                logLevel: verboseLogging ? .debug : .output
            )
        }

        // get the build output path
        let buildOutputPathCommand = "swift build -c \(buildConfiguration.rawValue) --show-bin-path"
        let dockerBuildOutputPath = try Utils.execute(
            executable: containerCLIPath,
            arguments: containerCLI.runArguments(
                baseImage: baseImage,
                workingDirectory: "/workspace",
                mounts: ["\(packageDirectory.path()):/workspace"],
                env: nil,
                command: buildOutputPathCommand
            ),
            logLevel: verboseLogging ? .debug : .silent
        )
        guard let buildPathOutput = dockerBuildOutputPath.split(separator: "\n").last else {
            throw BuilderErrors.failedParsingDockerOutput(dockerBuildOutputPath)
        }
        let buildOutputPath = URL(
            string: buildPathOutput.replacingOccurrences(of: "/workspace/", with: packageDirectory.description)
        )!

        // build the products
        var builtProducts = [String: URL]()
        for product in products {
            print("building \"\(product)\"")
            var buildCommand =
                "swift build -c \(buildConfiguration.rawValue) --product \(product) --static-swift-stdlib"
            if !noStrip {
                buildCommand += " -Xlinker -s"
            }
            if let localPath = ProcessInfo.processInfo.environment["LAMBDA_USE_LOCAL_DEPS"] {
                // when developing locally, we must have the full swift-aws-lambda-runtime project in the container
                // because Examples' Package.swift have a dependency on ../..
                // just like Package.swift's examples assume ../.., we assume we are two levels below the root project
                let slice = packageDirectory.pathComponents.suffix(2)
                try Utils.execute(
                    executable: containerCLIPath,
                    arguments: containerCLI.runArguments(
                        baseImage: baseImage,
                        workingDirectory: "/workspace/\(slice.joined(separator: "/"))",
                        mounts: ["\(packageDirectory.path())../..:/workspace"],
                        env: ["LAMBDA_USE_LOCAL_DEPS": localPath],
                        command: buildCommand
                    ),
                    logLevel: verboseLogging ? .debug : .output
                )
            } else {
                try Utils.execute(
                    executable: containerCLIPath,
                    arguments: containerCLI.runArguments(
                        baseImage: baseImage,
                        workingDirectory: "/workspace",
                        mounts: ["\(packageDirectory.path()):/workspace"],
                        env: nil,
                        command: buildCommand
                    ),
                    logLevel: verboseLogging ? .debug : .output
                )
            }
            let productPath = buildOutputPath.appending(path: product)

            guard FileManager.default.fileExists(atPath: productPath.path()) else {
                print("expected '\(product)' binary at \"\(productPath.path())\"")
                throw BuilderErrors.productExecutableNotFound(product)
            }
            builtProducts[product] = productPath
        }
        return builtProducts
    }

    // TODO: explore using ziplib or similar instead of shelling out
    private func package(
        packageName: String,
        products: [String: URL],
        zipToolPath: URL,
        outputDirectory: URL,
        verboseLogging: Bool
    ) throws -> [String: URL] {

        var archives = [String: URL]()
        for (product, artifactPath) in products {
            print("-------------------------------------------------------------------------")
            print("archiving \"\(product)\"")
            print("-------------------------------------------------------------------------")

            // prep zipfile location
            let workingDirectory = outputDirectory.appending(path: product)
            let zipfilePath = workingDirectory.appending(path: "\(product).zip")
            if FileManager.default.fileExists(atPath: workingDirectory.path()) {
                try FileManager.default.removeItem(atPath: workingDirectory.path())
            }
            try FileManager.default.createDirectory(atPath: workingDirectory.path(), withIntermediateDirectories: true)

            // rename artifact to "bootstrap"
            let relocatedArtifactPath = workingDirectory.appending(path: "bootstrap")
            try FileManager.default.copyItem(atPath: artifactPath.path(), toPath: relocatedArtifactPath.path())

            var arguments: [String] = []
            #if os(macOS) || os(Linux)
            arguments = [
                "--recurse-paths",
                "--symlinks",
                zipfilePath.lastPathComponent,
                relocatedArtifactPath.lastPathComponent,
            ]
            #else
            throw BuilderErrors.unsupportedPlatform("can't or don't know how to create a zip file on this platform")
            #endif

            // add resources
            var artifactPathComponents = artifactPath.pathComponents
            _ = artifactPathComponents.removeFirst()  // Get rid of beginning "/"
            _ = artifactPathComponents.removeLast()  // Get rid of the name of the package
            let artifactDirectory = "/\(artifactPathComponents.joined(separator: "/"))"
            for fileInArtifactDirectory in try FileManager.default.contentsOfDirectory(atPath: artifactDirectory) {
                guard let artifactURL = URL(string: "\(artifactDirectory)/\(fileInArtifactDirectory)") else {
                    continue
                }

                guard artifactURL.pathExtension == "resources" else {
                    continue  // Not resources, so don't copy
                }
                let resourcesDirectoryName = artifactURL.lastPathComponent
                let relocatedResourcesDirectory = workingDirectory.appending(path: resourcesDirectoryName)
                if FileManager.default.fileExists(atPath: artifactURL.path()) {
                    do {
                        arguments.append(resourcesDirectoryName)
                        try FileManager.default.copyItem(
                            atPath: artifactURL.path(),
                            toPath: relocatedResourcesDirectory.path()
                        )
                    } catch let error as CocoaError {

                        // On Linux, when the build has been done with Docker,
                        // the source file are owned by root
                        // this causes a permission error **after** the files have been copied
                        // see https://github.com/awslabs/swift-aws-lambda-runtime/issues/449
                        // see https://forums.swift.org/t/filemanager-copyitem-on-linux-fails-after-copying-the-files/77282

                        // because this error happens after the files have been copied, we can ignore it
                        // this code checks if the destination file exists
                        // if they do, just ignore error, otherwise throw it up to the caller.
                        if !(error.code == CocoaError.Code.fileWriteNoPermission
                            && FileManager.default.fileExists(atPath: relocatedResourcesDirectory.path()))
                        {
                            throw error
                        }  // else just ignore it
                    }
                }
            }

            // run the zip tool
            try Utils.execute(
                executable: zipToolPath,
                arguments: arguments,
                customWorkingDirectory: workingDirectory,
                logLevel: verboseLogging ? .debug : .silent
            )

            archives[product] = zipfilePath
        }
        return archives
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
            --no-strip                    Do not strip debug symbols from the binary.
            --help                        Show help information.
            """
        )
    }
}

@available(LambdaSwift 2.0, *)
enum CrossCompileMethod: String, CustomStringConvertible {
    case docker
    case container
    case swiftStaticSdk = "swift-static-sdk"
    case customSdk = "custom-sdk"

    var isSupported: Bool {
        switch self {
        case .docker, .container: return true
        case .swiftStaticSdk, .customSdk: return false
        }
    }

    static func parse(_ value: String?) throws -> Self {
        guard let value else {
            return .docker
        }

        guard let method = CrossCompileMethod(rawValue: value.lowercased()) else {
            throw BuilderErrors.invalidArgument(
                "invalid cross-compile method '\(value)'. Use 'docker', 'container', 'swift-static-sdk', or 'custom-sdk'."
            )
        }

        guard method.isSupported else {
            throw BuilderErrors.unsupportedCrossCompileMethod(method)
        }

        return method
    }

    /// Returns the container CLI pull arguments for the given image.
    func pullArguments(image: String) -> [String] {
        switch self {
        case .docker:
            return ["pull", image]
        case .container:
            return ["image", "pull", image]
        case .swiftStaticSdk, .customSdk:
            fatalError("pullArguments should not be called for unsupported cross-compile methods")
        }
    }

    /// Returns the container CLI run arguments for the given configuration.
    func runArguments(
        baseImage: String,
        workingDirectory: String,
        mounts: [String],
        env: [String: String]?,
        command: String
    ) -> [String] {
        func genericArgs() -> [String] {
            var args: [String] = ["run", "--rm"]
            for mount in mounts {
                args += ["-v", mount]
            }
            if let env {
                for (key, value) in env.sorted(by: { $0.key < $1.key }) {
                    args += ["-e", "\(key)=\(value)"]
                }
            }
            args += ["-w", workingDirectory, baseImage, "bash", "-cl", command]
            return args
        }
        switch self {

        case .docker:
            return genericArgs()

        case .container:
            var args = genericArgs()

            // container's runtime needs a bit more memory
            if self == .container {
                args.insert("--memory", at: 1)
                args.insert("4G", at: 2)
            }

            return args

        case .swiftStaticSdk, .customSdk:
            fatalError("runArguments should not be called for unsupported cross-compile methods")
        }
    }

    var description: String {
        self.rawValue
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
    public let noStrip: Bool
    public let explicitAL2Image: Bool

    // passed by the plugin
    public let packageID: String
    public let packageDisplayName: String
    public let packageDirectory: URL
    public let dockerToolPath: URL
    public let zipToolPath: URL

    public init(arguments: [String]) throws {
        var argumentExtractor = ArgumentExtractor(arguments)

        let verboseArgument = argumentExtractor.extractFlag(named: "verbose") > 0
        let outputPathArgument = argumentExtractor.extractOption(named: "output-path")
        let outputDirectoryArgument = argumentExtractor.extractOption(named: "output-directory")
        let packageIDArgument = argumentExtractor.extractOption(named: "package-id")
        let packageDisplayNameArgument = argumentExtractor.extractOption(named: "package-display-name")
        let packageDirectoryArgument = argumentExtractor.extractOption(named: "package-directory")
        let dockerToolPathArgument = argumentExtractor.extractOption(named: "docker-tool-path")
        let zipToolPathArgument = argumentExtractor.extractOption(named: "zip-tool-path")
        let productsArgument = argumentExtractor.extractOption(named: "products")
        let configurationArgument = argumentExtractor.extractOption(named: "configuration")
        let swiftVersionArgument = argumentExtractor.extractOption(named: "swift-version")
        let baseDockerImageArgument = argumentExtractor.extractOption(named: "base-docker-image")
        let disableDockerImageUpdateArgument = argumentExtractor.extractFlag(named: "disable-docker-image-update") > 0
        let crossCompileArgument = argumentExtractor.extractOption(named: "cross-compile")
        let containerCliArgument = argumentExtractor.extractOption(named: "container-cli")  // deprecated alias
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

        // docker tool path
        guard !dockerToolPathArgument.isEmpty else {
            throw BuilderErrors.invalidArgument("--docker-tool-path argument is required")
        }
        self.dockerToolPath = URL(fileURLWithPath: dockerToolPathArgument.first!)

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
        // --container-cli is a deprecated alias for --cross-compile (backward compatibility)
        let resolvedCrossCompile = crossCompileArgument.first ?? containerCliArgument.first
        self.crossCompileMethod = try CrossCompileMethod.parse(resolvedCrossCompile)
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

    var description: String {
        """
        {
          outputDirectory: \(self.outputDirectory)
          products: \(self.products)
          buildConfiguration: \(self.buildConfiguration)
          dockerToolPath: \(self.dockerToolPath)
          baseDockerImage: \(self.baseDockerImage)
          disableDockerImageUpdate: \(self.disableDockerImageUpdate)
          crossCompileMethod: \(self.crossCompileMethod)
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
