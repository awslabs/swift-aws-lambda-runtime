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

@available(macOS 15.0, *)
struct Builder {
    func build(arguments: [String]) async throws {
        let configuration = try BuilderConfiguration(arguments: arguments)

        if configuration.help {
            self.displayHelpMessage()
            return
        }

        let builtProducts: [String: URL]

        // build with docker
        // TODO: check if dockerToolPath is provided
        // When not provided, it means we're building on Amazon Linux 2
        builtProducts = try self.buildInDocker(
            packageIdentity: configuration.packageID,
            packageDirectory: configuration.packageDirectory,
            products: configuration.products,
            dockerToolPath: configuration.dockerToolPath,
            outputDirectory: configuration.outputDirectory,
            baseImage: configuration.baseDockerImage,
            disableDockerImageUpdate: configuration.disableDockerImageUpdate,
            buildConfiguration: configuration.buildConfiguration,
            verboseLogging: configuration.verboseLogging
        )

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

    private func buildInDocker(
        packageIdentity: String,
        packageDirectory: URL,
        products: [String],
        dockerToolPath: URL,
        outputDirectory: URL,
        baseImage: String,
        disableDockerImageUpdate: Bool,
        buildConfiguration: BuildConfiguration,
        verboseLogging: Bool
    ) throws -> [String: URL] {

        print("-------------------------------------------------------------------------")
        print("building \"\(packageIdentity)\" in docker")
        print("-------------------------------------------------------------------------")

        if !disableDockerImageUpdate {
            // update the underlying docker image, if necessary
            print("updating \"\(baseImage)\" docker image")
            try Utils.execute(
                executable: dockerToolPath,
                arguments: ["pull", baseImage],
                logLevel: verboseLogging ? .debug : .silent
            )
        }

        // get the build output path
        let buildOutputPathCommand = "swift build -c \(buildConfiguration.rawValue) --show-bin-path"
        let dockerBuildOutputPath = try Utils.execute(
            executable: dockerToolPath,
            arguments: [
                "run", "--rm", "-v", "\(packageDirectory.path()):/workspace", "-w", "/workspace", baseImage, "bash",
                "-cl", buildOutputPathCommand,
            ],
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
            let buildCommand =
                "swift build -c \(buildConfiguration.rawValue) --product \(product) --static-swift-stdlib"
            if let localPath = ProcessInfo.processInfo.environment["LAMBDA_USE_LOCAL_DEPS"] {
                // when developing locally, we must have the full swift-aws-lambda-runtime project in the container
                // because Examples' Package.swift have a dependency on ../..
                // just like Package.swift's examples assume ../.., we assume we are two levels below the root project
                let slice = packageDirectory.pathComponents.suffix(2)
                try Utils.execute(
                    executable: dockerToolPath,
                    arguments: [
                        "run", "--rm", "--env", "LAMBDA_USE_LOCAL_DEPS=\(localPath)", "-v",
                        "\(packageDirectory.path())../..:/workspace", "-w",
                        "/workspace/\(slice.joined(separator: "/"))", baseImage, "bash", "-cl", buildCommand,
                    ],
                    logLevel: verboseLogging ? .debug : .output
                )
            } else {
                try Utils.execute(
                    executable: dockerToolPath,
                    arguments: [
                        "run", "--rm", "-v", "\(packageDirectory.path()):/workspace", "-w", "/workspace", baseImage,
                        "bash", "-cl", buildCommand,
                    ],
                    logLevel: verboseLogging ? .debug : .output
                )
            }
            let productPath = buildOutputPath.appending(path: product)

            guard FileManager.default.fileExists(atPath: productPath.path()) else {
                print("expected '\(product)' binary at \"\(productPath.path())\"")
                throw BuilderErrors.productExecutableNotFound(product)
            }
            builtProducts[.init(product)] = productPath
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
            throw Errors.unsupportedPlatform("can't or don't know how to create a zip file on this platform")
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

    private func displayHelpMessage() {
        print(
            """
            OVERVIEW: A SwiftPM plugin to build and package your lambda function.

            REQUIREMENTS: To use this plugin, you must have docker installed and started.

            USAGE: swift package --allow-network-connections docker lambda-build
                                                       [--help] [--verbose]
                                                       [--output-path <path>]
                                                       [--products <list of products>]
                                                       [--configuration debug | release]
                                                       [--swift-version <version>]
                                                       [--base-docker-image <docker_image_name>]
                                                       [--disable-docker-image-update]
                                                     

            OPTIONS:
            --verbose                     Produce verbose output for debugging.
            --output-path <path>          The path of the binary package.
                                          (default is `.build/plugins/AWSLambdaPackager/outputs/...`)
            --products <list>             The list of executable targets to build.
                                          (default is taken from Package.swift)
            --configuration <name>        The build configuration (debug or release)
                                          (default is release)
            --swift-version               The swift version to use for building.
                                          (default is latest)
                                          This parameter cannot be used when --base-docker-image  is specified.
            --base-docker-image <name>    The name of the base docker image to use for the build.
                                          (default : swift-<version>:amazonlinux2)
                                          This parameter cannot be used when --swift-version is specified.
            --disable-docker-image-update Do not attempt to update the docker image
            --help                        Show help information.
            """
        )
    }
}

private struct BuilderConfiguration: CustomStringConvertible {

    // passed by the user
    public let help: Bool
    public let outputDirectory: URL
    public let products: [String]
    public let buildConfiguration: BuildConfiguration
    public let verboseLogging: Bool
    public let baseDockerImage: String
    public let disableDockerImageUpdate: Bool

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
        guard !outputPathArgument.isEmpty else {
            throw BuilderErrors.invalidArgument("--output-path is required")
        }
        self.outputDirectory = URL(fileURLWithPath: outputPathArgument.first!)

        // products
        guard !productsArgument.isEmpty else {
            throw BuilderErrors.invalidArgument("--products argument is required")
        }
        self.products = productsArgument.flatMap { $0.split(separator: ",").map(String.init) }

        // build configuration
        guard let buildConfigurationName = configurationArgument.first else {
            throw BuilderErrors.invalidArgument("--configuration argument is equired")
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
            baseDockerImageArgument.first ?? "swift:\(swiftVersion.map { $0 + "-" } ?? "")amazonlinux2"

        self.disableDockerImageUpdate = disableDockerImageUpdateArgument

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
          zipToolPath: \(self.zipToolPath)
          packageID: \(self.packageID) 
          packageDisplayName: \(self.packageDisplayName)
          packageDirectory: \(self.packageDirectory)
        }
        """
    }
}

private enum BuilderErrors: Error, CustomStringConvertible {
    case invalidArgument(String)
    case unsupportedPlatform(String)
    case unknownProduct(String)
    case productExecutableNotFound(String)
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
        case .failedWritingDockerfile:
            return "failed writing dockerfile"
        case .failedParsingDockerOutput(let output):
            return "failed parsing docker output: '\(output)'"
        case .processFailed(let arguments, let code):
            return "\(arguments.joined(separator: " ")) failed with code \(code)"
        }
    }
}

private enum BuildConfiguration: String {
    case debug
    case release
}
