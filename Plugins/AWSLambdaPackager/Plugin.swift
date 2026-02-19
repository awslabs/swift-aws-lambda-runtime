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

import Foundation
import PackagePlugin

@main
@available(macOS 15.0, *)
struct AWSLambdaPackager: CommandPlugin {
    func performCommand(context: PackagePlugin.PluginContext, arguments: [String]) async throws {
        let configuration = try Configuration(context: context, arguments: arguments)

        if configuration.help {
            self.displayHelpMessage()
            return
        }

        guard !configuration.products.isEmpty else {
            throw Errors.unknownProduct("no appropriate products found to package")
        }

        if configuration.products.count > 1 && !configuration.explicitProducts {
            let productNames = configuration.products.map(\.name)
            print(
                "No explicit products named, building all executable products: '\(productNames.joined(separator: "', '"))'"
            )
        }

        let builtProducts: [LambdaProduct: URL]
        if self.isAmazonLinux() {
            // build directly on the machine
            builtProducts = try self.build(
                packageIdentity: context.package.id,
                products: configuration.products,
                buildConfiguration: configuration.buildConfiguration,
                verboseLogging: configuration.verboseLogging
            )
        } else {
            // build with docker
            builtProducts = try self.buildInDocker(
                packageIdentity: context.package.id,
                packageDirectory: context.package.directoryURL,
                products: configuration.products,
                toolsProvider: { name in try context.tool(named: name).url },
                outputDirectory: configuration.outputDirectory,
                containerCLI: configuration.containerCLI,
                baseImage: configuration.baseDockerImage,
                disableDockerImageUpdate: configuration.disableDockerImageUpdate,
                buildConfiguration: configuration.buildConfiguration,
                verboseLogging: configuration.verboseLogging
            )
        }

        // create the archive
        let archives = try self.package(
            packageName: context.package.displayName,
            products: builtProducts,
            toolsProvider: { name in try context.tool(named: name).url },
            outputDirectory: configuration.outputDirectory,
            verboseLogging: configuration.verboseLogging
        )

        print(
            "\(archives.count > 0 ? archives.count.description : "no") archive\(archives.count != 1 ? "s" : "") created"
        )
        for (product, archivePath) in archives {
            print("  * \(product.name) at \(archivePath.path())")
        }
    }

    private func buildInDocker(
        packageIdentity: Package.ID,
        packageDirectory: URL,
        products: [Product],
        toolsProvider: (String) throws -> URL,
        outputDirectory: URL,
        containerCLI: ContainerCLI,
        baseImage: String,
        disableDockerImageUpdate: Bool,
        buildConfiguration: PackageManager.BuildConfiguration,
        verboseLogging: Bool
    ) throws -> [LambdaProduct: URL] {
        let containerCLIPath = try toolsProvider(containerCLI.executableName)

        print("-------------------------------------------------------------------------")
        print("building \"\(packageIdentity)\" in \(containerCLI.displayName)")
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
            throw Errors.failedParsingDockerOutput(dockerBuildOutputPath)
        }
        let buildOutputPath = URL(
            string: buildPathOutput.replacingOccurrences(of: "/workspace/", with: packageDirectory.description)
        )!

        // build the products
        var builtProducts = [LambdaProduct: URL]()
        for product in products {
            print("building \"\(product.name)\"")
            let buildCommand =
                "swift build -c \(buildConfiguration.rawValue) --product \(product.name) --static-swift-stdlib"
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
            let productPath = buildOutputPath.appending(path: product.name)

            guard FileManager.default.fileExists(atPath: productPath.path()) else {
                Diagnostics.error("expected '\(product.name)' binary at \"\(productPath.path())\"")
                throw Errors.productExecutableNotFound(product.name)
            }
            builtProducts[.init(product)] = productPath
        }
        return builtProducts
    }

    private func build(
        packageIdentity: Package.ID,
        products: [Product],
        buildConfiguration: PackageManager.BuildConfiguration,
        verboseLogging: Bool
    ) throws -> [LambdaProduct: URL] {
        print("-------------------------------------------------------------------------")
        print("building \"\(packageIdentity)\"")
        print("-------------------------------------------------------------------------")

        var results = [LambdaProduct: URL]()
        for product in products {
            print("building \"\(product.name)\"")
            var parameters = PackageManager.BuildParameters()
            parameters.configuration = buildConfiguration
            parameters.otherSwiftcFlags = ["-static-stdlib"]
            parameters.logging = verboseLogging ? .verbose : .concise

            let result = try packageManager.build(
                .product(product.name),
                parameters: parameters
            )
            guard let artifact = result.executableArtifact(for: product) else {
                throw Errors.productExecutableNotFound(product.name)
            }
            results[.init(product)] = artifact.url
        }
        return results
    }

    // TODO: explore using ziplib or similar instead of shelling out
    private func package(
        packageName: String,
        products: [LambdaProduct: URL],
        toolsProvider: (String) throws -> URL,
        outputDirectory: URL,
        verboseLogging: Bool
    ) throws -> [LambdaProduct: URL] {
        let zipToolPath = try toolsProvider("zip")

        var archives = [LambdaProduct: URL]()
        for (product, artifactPath) in products {
            print("-------------------------------------------------------------------------")
            print("archiving \"\(product.name)\"")
            print("-------------------------------------------------------------------------")

            // prep zipfile location
            let workingDirectory = outputDirectory.appending(path: product.name)
            let zipfilePath = workingDirectory.appending(path: "\(product.name).zip")
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

    private func isAmazonLinux() -> Bool {
        if let data = FileManager.default.contents(atPath: "/etc/system-release"),
            let release = String(data: data, encoding: .utf8)
        {
            return release.hasPrefix("Amazon Linux")
        } else {
            return false
        }
    }

    private func displayHelpMessage() {
        print(
            """
            OVERVIEW: A SwiftPM plugin to build and package your lambda function.

            REQUIREMENTS: To use this plugin, you must have docker or container installed and started.

            USAGE: swift package --allow-network-connections docker archive
                                                       [--help] [--verbose]
                                                       [--output-path <path>]
                                                       [--products <list of products>]
                                                       [--configuration debug | release]
                                                       [--swift-version <version>]
                                                       [--base-docker-image <docker_image_name>]
                                                       [--disable-docker-image-update]
                                                       [--container-cli <docker | container>]
                                                      

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
            --container-cli <name>        The container CLI to use (docker or container)
                                          (default is docker)
            --help                        Show help information.
            """
        )
    }
}

@available(macOS 15.0, *)
private enum ContainerCLI: String, CustomStringConvertible {
    case docker
    case container

    var executableName: String {
        self.rawValue
    }

    var displayName: String {
        self.rawValue
    }

    static func parse(_ value: String?) throws -> Self {
        guard let value else {
            return .docker
        }

        guard let tool = ContainerCLI(rawValue: value.lowercased()) else {
            throw Errors.invalidArgument("invalid container CLI '\(value)'. Use 'docker' or 'container'.")
        }
        return tool
    }

    func pullArguments(image: String) -> [String] {
        switch self {
        case .docker:
            return ["pull", image]
        case .container:
            return ["image", "pull", image]
        }
    }

    func runArguments(
        baseImage: String,
        workingDirectory: String,
        mounts: [String],
        env: [String: String]?,
        command: String
    ) -> [String] {
        var args: [String] = ["run", "--rm"]
        for mount in mounts {
            args += ["-v", mount]
        }
        if let env {
            for (key, value) in env.sorted(by: { $0.key < $1.key }) {
                args += ["--env", "\(key)=\(value)"]
            }
        }
        args += ["-w", workingDirectory, baseImage, "bash", "-cl", command]
        return args
    }

    var description: String {
        self.rawValue
    }
}

@available(macOS 15.0, *)
private struct Configuration: CustomStringConvertible {
    public let help: Bool
    public let outputDirectory: URL
    public let products: [Product]
    public let explicitProducts: Bool
    public let buildConfiguration: PackageManager.BuildConfiguration
    public let verboseLogging: Bool
    public let baseDockerImage: String
    public let disableDockerImageUpdate: Bool
    public let containerCLI: ContainerCLI

    public init(
        context: PluginContext,
        arguments: [String]
    ) throws {
        var argumentExtractor = ArgumentExtractor(arguments)
        let verboseArgument = argumentExtractor.extractFlag(named: "verbose") > 0
        let outputPathArgument = argumentExtractor.extractOption(named: "output-path")
        let productsArgument = argumentExtractor.extractOption(named: "products")
        let configurationArgument = argumentExtractor.extractOption(named: "configuration")
        let swiftVersionArgument = argumentExtractor.extractOption(named: "swift-version")
        let baseDockerImageArgument = argumentExtractor.extractOption(named: "base-docker-image")
        let disableDockerImageUpdateArgument = argumentExtractor.extractFlag(named: "disable-docker-image-update") > 0
        let containerCliArgument = argumentExtractor.extractOption(named: "container-cli")
        let helpArgument = argumentExtractor.extractFlag(named: "help") > 0

        // help required ?
        self.help = helpArgument

        // verbose logging required ?
        self.verboseLogging = verboseArgument

        if let outputPath = outputPathArgument.first {
            #if os(Linux)
            var isDirectory: Bool = false
            #else
            var isDirectory: ObjCBool = false
            #endif
            guard FileManager.default.fileExists(atPath: outputPath, isDirectory: &isDirectory)
            else {
                throw Errors.invalidArgument("invalid output directory '\(outputPath)'")
            }
            self.outputDirectory = URL(string: outputPath)!
        } else {
            self.outputDirectory = context.pluginWorkDirectoryURL.appending(path: "\(AWSLambdaPackager.self)")
        }

        self.explicitProducts = !productsArgument.isEmpty
        if self.explicitProducts {
            let products = try context.package.products(named: productsArgument)
            for product in products {
                guard product is ExecutableProduct else {
                    throw Errors.invalidArgument("product named '\(product.name)' is not an executable product")
                }
            }
            self.products = products

        } else {
            self.products = context.package.products.filter { $0 is ExecutableProduct }
        }

        if let buildConfigurationName = configurationArgument.first {
            guard let buildConfiguration = PackageManager.BuildConfiguration(rawValue: buildConfigurationName) else {
                throw Errors.invalidArgument("invalid build configuration named '\(buildConfigurationName)'")
            }
            self.buildConfiguration = buildConfiguration
        } else {
            self.buildConfiguration = .release
        }

        guard !(!swiftVersionArgument.isEmpty && !baseDockerImageArgument.isEmpty) else {
            throw Errors.invalidArgument("--swift-version and --base-docker-image are mutually exclusive")
        }

        let swiftVersion = swiftVersionArgument.first ?? .none  // undefined version will yield the latest docker image
        self.baseDockerImage =
            baseDockerImageArgument.first ?? "swift:\(swiftVersion.map { $0 + "-" } ?? "")amazonlinux2"

        self.disableDockerImageUpdate = disableDockerImageUpdateArgument
        self.containerCLI = try ContainerCLI.parse(
            containerCliArgument.first
        )

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
          products: \(self.products.map(\.name))
          buildConfiguration: \(self.buildConfiguration)
          baseDockerImage: \(self.baseDockerImage)
          disableDockerImageUpdate: \(self.disableDockerImageUpdate)
          containerCLI: \(self.containerCLI)
        }
        """
    }

}

private enum ProcessLogLevel: Comparable {
    case silent
    case output(outputIndent: Int)
    case debug(outputIndent: Int)

    var naturalOrder: Int {
        switch self {
        case .silent:
            return 0
        case .output:
            return 1
        case .debug:
            return 2
        }
    }

    static var output: Self {
        .output(outputIndent: 2)
    }

    static var debug: Self {
        .debug(outputIndent: 2)
    }

    static func < (lhs: ProcessLogLevel, rhs: ProcessLogLevel) -> Bool {
        lhs.naturalOrder < rhs.naturalOrder
    }
}

private enum Errors: Error, CustomStringConvertible {
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

private struct LambdaProduct: Hashable {
    let underlying: Product

    init(_ underlying: Product) {
        self.underlying = underlying
    }

    var name: String {
        self.underlying.name
    }

    func hash(into hasher: inout Hasher) {
        self.underlying.id.hash(into: &hasher)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.underlying.id == rhs.underlying.id
    }
}

extension PackageManager.BuildResult {
    // find the executable produced by the build
    func executableArtifact(for product: Product) -> PackageManager.BuildResult.BuiltArtifact? {
        let executables = self.builtArtifacts.filter {
            $0.kind == .executable && $0.url.lastPathComponent == product.name
        }
        guard !executables.isEmpty else {
            return nil
        }
        guard executables.count == 1, let executable = executables.first else {
            return nil
        }
        return executable
    }
}
