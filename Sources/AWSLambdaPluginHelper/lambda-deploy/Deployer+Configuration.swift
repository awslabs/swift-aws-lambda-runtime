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
struct DeployerConfiguration: CustomStringConvertible {
    let help: Bool
    let verboseLogging: Bool
    let withURL: Bool
    let delete: Bool
    let region: String?
    let profile: String?
    let iamRole: String?
    let inputDirectory: URL?
    /// The architecture resolved for deployment: the explicitly requested one, else the host.
    /// The deployer reconciles this against the build manifest (see `explicitArchitecture`).
    let architecture: Architecture
    /// The architecture the user requested via `--architecture`, or `nil` when omitted. When set,
    /// the deployer treats a disagreement with the built artifact as a hard error rather than
    /// silently deploying a function whose declared architecture does not match its binary.
    ///
    /// This is primarily useful for deploying an artifact that was *not* produced by `lambda-build`
    /// (e.g. a ZIP from the legacy `archive` command, or one supplied via `--input-directory`) and
    /// therefore has no build manifest to read the architecture from. In the normal
    /// `lambda-build` → `lambda-deploy` flow the manifest already records the architecture, so this
    /// flag only acts as an optional assertion against it.
    let explicitArchitecture: Architecture?
    let products: [String]
    /// Container CLI to use for an image (OCI) deploy: `docker` or `container`. `nil` → resolved
    /// from the build manifest, falling back to docker. Mirrors `lambda-build --cross-compile`.
    let crossCompile: String?
    /// Resolved paths to the container CLI executables, keyed by CLI name (`docker`, `container`),
    /// injected by the plugin wrapper. The plugin resolves every CLI it can find up front (the
    /// sandbox only runs tools resolved ahead of time) because the CLI flavor to use is only known
    /// after reading the build manifest. Empty for a plain ZIP deploy (no container CLI needed).
    let crossCompileToolPaths: [String: URL]

    enum Architecture: String {
        case x64
        case arm64

        static var host: Architecture {
            #if arch(x86_64)
            return .x64
            #else
            return .arm64
            #endif
        }
    }

    init(arguments: [String]) throws {
        var argumentExtractor = ArgumentExtractor(arguments)

        let helpArgument = argumentExtractor.extractFlag(named: "help") > 0
        let verboseArgument = argumentExtractor.extractFlag(named: "verbose") > 0
        let withURLArgument = argumentExtractor.extractFlag(named: "with-url") > 0
        let deleteArgument = argumentExtractor.extractFlag(named: "delete") > 0
        let regionArgument = argumentExtractor.extractOption(named: "region")
        let profileArgument = argumentExtractor.extractOption(named: "profile")
        let iamRoleArgument = argumentExtractor.extractOption(named: "iam-role")
        let inputDirectoryArgument = argumentExtractor.extractOption(named: "input-directory")
        let architectureArgument = argumentExtractor.extractOption(named: "architecture")
        let productsArgument = argumentExtractor.extractOption(named: "products")
        let crossCompileArgument = argumentExtractor.extractOption(named: "cross-compile")
        let crossCompileToolPathArgument = argumentExtractor.extractOption(named: "cross-compile-tool-path")

        // help required?
        self.help = helpArgument

        // verbose logging required?
        self.verboseLogging = verboseArgument

        // create a Function URL?
        self.withURL = withURLArgument

        // delete the function?
        self.delete = deleteArgument

        // AWS region (nil means Soto resolves it)
        self.region = regionArgument.first

        // AWS profile from ~/.aws/config (nil means default credential chain)
        self.profile = profileArgument.first

        // IAM role ARN (nil means create a new role)
        self.iamRole = iamRoleArgument.first

        // input directory for the ZIP archive
        if let inputDir = inputDirectoryArgument.first {
            self.inputDirectory = URL(fileURLWithPath: inputDir)
        } else {
            self.inputDirectory = nil
        }

        // architecture
        if let archString = architectureArgument.first {
            guard let arch = Architecture(rawValue: archString) else {
                throw DeployerErrors.invalidArchitecture(archString)
            }
            self.architecture = arch
            self.explicitArchitecture = arch
        } else {
            self.architecture = .host
            self.explicitArchitecture = nil
        }

        // products
        self.products = productsArgument.flatMap { $0.split(separator: ",").map(String.init) }

        // container CLI for image deploys (nil → resolved from the build manifest)
        self.crossCompile = crossCompileArgument.first?.lowercased()

        // Resolved container CLI paths, forwarded by the plugin as `--cross-compile-tool-path
        // <name>=<path>` (one per available CLI). A bare path with no `name=` prefix is treated as
        // docker for backward compatibility with older plugin wrappers and existing tests.
        var toolPaths: [String: URL] = [:]
        for entry in crossCompileToolPathArgument {
            if let separator = entry.firstIndex(of: "="), separator != entry.startIndex {
                let name = String(entry[..<separator]).lowercased()
                let path = String(entry[entry.index(after: separator)...])
                toolPaths[name] = URL(fileURLWithPath: path)
            } else {
                toolPaths["docker"] = URL(fileURLWithPath: entry)
            }
        }
        self.crossCompileToolPaths = toolPaths
    }

    var description: String {
        """
        {
          verboseLogging: \(self.verboseLogging)
          withURL: \(self.withURL)
          delete: \(self.delete)
          region: \(self.region ?? "<resolved from AWS config>")
          profile: \(self.profile ?? "<default>")
          iamRole: \(self.iamRole ?? "<create new>")
          inputDirectory: \(self.inputDirectory?.path() ?? "<default build output>")
          architecture: \(self.architecture.rawValue)\(self.explicitArchitecture == nil ? " <default>" : " <explicit>")
          products: \(self.products)
          crossCompile: \(self.crossCompile ?? "<from manifest>")
          crossCompileToolPaths: \(self.crossCompileToolPaths.isEmpty ? "<none>" : self.crossCompileToolPaths.map { "\($0.key)=\($0.value.path())" }.sorted().joined(separator: ", "))
        }
        """
    }
}
