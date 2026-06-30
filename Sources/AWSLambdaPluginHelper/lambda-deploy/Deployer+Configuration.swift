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
    let architecture: Architecture
    let products: [String]
    /// Container CLI to use for an image (OCI) deploy: `docker` or `container`. `nil` → resolved
    /// from the build manifest, falling back to docker. Mirrors `lambda-build --cross-compile`.
    let crossCompile: String?
    /// Resolved path to the container CLI executable, injected by the plugin wrapper. `nil` when the
    /// deploy is a plain ZIP (no container CLI needed).
    let crossCompileToolPath: URL?

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
        } else {
            self.architecture = .host
        }

        // products
        self.products = productsArgument.flatMap { $0.split(separator: ",").map(String.init) }

        // container CLI for image deploys (nil → resolved from the build manifest)
        self.crossCompile = crossCompileArgument.first
        if let toolPath = crossCompileToolPathArgument.first {
            self.crossCompileToolPath = URL(fileURLWithPath: toolPath)
        } else {
            self.crossCompileToolPath = nil
        }
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
          architecture: \(self.architecture.rawValue)
          products: \(self.products)
          crossCompile: \(self.crossCompile ?? "<from manifest>")
          crossCompileToolPath: \(self.crossCompileToolPath?.path() ?? "<none>")
        }
        """
    }
}
