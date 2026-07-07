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

@Suite("DeployerConfiguration argument parsing")
struct DeployerConfigurationTests {

    // MARK: - Architecture parsing (Requirement 3.14)

    @available(LambdaSwift 2.0, *)
    @Test("Valid architecture x64 is parsed correctly")
    func architectureX64() throws {
        let config = try DeployerConfiguration(arguments: ["--architecture", "x64"])
        #expect(config.architecture == .x64)
    }

    @available(LambdaSwift 2.0, *)
    @Test("Valid architecture arm64 is parsed correctly")
    func architectureArm64() throws {
        let config = try DeployerConfiguration(arguments: ["--architecture", "arm64"])
        #expect(config.architecture == .arm64)
    }

    @available(LambdaSwift 2.0, *)
    @Test("Invalid architecture throws error")
    func invalidArchitectureThrows() throws {
        #expect(throws: DeployerErrors.self) {
            _ = try DeployerConfiguration(arguments: ["--architecture", "mips"])
        }
    }

    @available(LambdaSwift 2.0, *)
    @Test("Invalid architecture value produces descriptive error")
    func invalidArchitectureMessage() throws {
        do {
            _ = try DeployerConfiguration(arguments: ["--architecture", "sparc"])
            Issue.record("Expected an error to be thrown")
        } catch let error as DeployerErrors {
            let description = error.description
            #expect(description.contains("sparc"))
            #expect(description.contains("x64") || description.contains("arm64"))
        }
    }

    // MARK: - Default architecture matches host (Requirement 3.13)

    @available(LambdaSwift 2.0, *)
    @Test("Default architecture matches host when --architecture is omitted")
    func defaultArchitectureMatchesHost() throws {
        let config = try DeployerConfiguration(arguments: [])
        #expect(config.architecture == .host)
        // Verify .host resolves to a valid value on this machine
        #if arch(x86_64)
        #expect(config.architecture == .x64)
        #else
        #expect(config.architecture == .arm64)
        #endif
    }

    // MARK: - Explicit vs default architecture (issue #683)

    @available(LambdaSwift 2.0, *)
    @Test("explicitArchitecture is set when --architecture is passed")
    func explicitArchitectureSet() throws {
        let config = try DeployerConfiguration(arguments: ["--architecture", "arm64"])
        #expect(config.explicitArchitecture == .arm64)
        #expect(config.architecture == .arm64)
    }

    @available(LambdaSwift 2.0, *)
    @Test("explicitArchitecture is nil when --architecture is omitted")
    func explicitArchitectureNilWhenOmitted() throws {
        let config = try DeployerConfiguration(arguments: [])
        #expect(config.explicitArchitecture == nil)
        #expect(config.architecture == .host)
    }

    // MARK: - Region parsing (Requirement 3.25)

    @available(LambdaSwift 2.0, *)
    @Test("Region is parsed from arguments")
    func regionParsing() throws {
        let config = try DeployerConfiguration(arguments: ["--region", "eu-west-1"])
        #expect(config.region == "eu-west-1")
    }

    @available(LambdaSwift 2.0, *)
    @Test("Region is nil when not specified")
    func regionDefaultNil() throws {
        let config = try DeployerConfiguration(arguments: [])
        #expect(config.region == nil)
    }

    @available(LambdaSwift 2.0, *)
    @Test("Region with equals syntax is parsed")
    func regionEqualsSyntax() throws {
        let config = try DeployerConfiguration(arguments: ["--region=us-west-2"])
        #expect(config.region == "us-west-2")
    }

    // MARK: - IAM role parsing

    @available(LambdaSwift 2.0, *)
    @Test("IAM role is parsed from arguments")
    func iamRoleParsing() throws {
        let roleArn = "arn:aws:iam::123456789012:role/my-role"
        let config = try DeployerConfiguration(arguments: ["--iam-role", roleArn])
        #expect(config.iamRole == roleArn)
    }

    @available(LambdaSwift 2.0, *)
    @Test("IAM role is nil when not specified")
    func iamRoleDefaultNil() throws {
        let config = try DeployerConfiguration(arguments: [])
        #expect(config.iamRole == nil)
    }

    // MARK: - Input directory parsing

    @available(LambdaSwift 2.0, *)
    @Test("Input directory is parsed from arguments")
    func inputDirectoryParsing() throws {
        let config = try DeployerConfiguration(arguments: ["--input-directory", "/tmp/build/output"])
        #expect(config.inputDirectory != nil)
        #expect(config.inputDirectory?.path().contains("/tmp/build/output") == true)
    }

    @available(LambdaSwift 2.0, *)
    @Test("Input directory is nil when not specified")
    func inputDirectoryDefaultNil() throws {
        let config = try DeployerConfiguration(arguments: [])
        #expect(config.inputDirectory == nil)
    }

    // MARK: - Cross-compile (image deploy) parsing

    @available(LambdaSwift 2.0, *)
    @Test("--cross-compile and name-keyed --cross-compile-tool-path are parsed")
    func crossCompileParsing() throws {
        let config = try DeployerConfiguration(arguments: [
            "--cross-compile", "container",
            "--cross-compile-tool-path", "docker=/usr/local/bin/docker",
            "--cross-compile-tool-path", "container=/usr/local/bin/container",
        ])
        #expect(config.crossCompile == "container")
        #expect(config.crossCompileToolPaths["docker"]?.path().contains("/usr/local/bin/docker") == true)
        #expect(config.crossCompileToolPaths["container"]?.path().contains("/usr/local/bin/container") == true)
    }

    @available(LambdaSwift 2.0, *)
    @Test("a bare --cross-compile-tool-path is treated as docker for backward compatibility")
    func crossCompileToolPathBareIsDocker() throws {
        let config = try DeployerConfiguration(arguments: [
            "--cross-compile-tool-path", "/usr/local/bin/docker",
        ])
        #expect(config.crossCompileToolPaths["docker"]?.path().contains("/usr/local/bin/docker") == true)
    }

    @available(LambdaSwift 2.0, *)
    @Test("cross-compile options default to empty (resolved from the build manifest)")
    func crossCompileDefaultsNil() throws {
        let config = try DeployerConfiguration(arguments: [])
        #expect(config.crossCompile == nil)
        #expect(config.crossCompileToolPaths.isEmpty)
    }

    // MARK: - With URL flag parsing

    @available(LambdaSwift 2.0, *)
    @Test("--with-url flag is detected")
    func withURLFlag() throws {
        let config = try DeployerConfiguration(arguments: ["--with-url"])
        #expect(config.withURL == true)
    }

    @available(LambdaSwift 2.0, *)
    @Test("--with-url defaults to false")
    func withURLDefaultFalse() throws {
        let config = try DeployerConfiguration(arguments: [])
        #expect(config.withURL == false)
    }

    // MARK: - Delete flag parsing

    @available(LambdaSwift 2.0, *)
    @Test("--delete flag is detected")
    func deleteFlag() throws {
        let config = try DeployerConfiguration(arguments: ["--delete"])
        #expect(config.delete == true)
    }

    @available(LambdaSwift 2.0, *)
    @Test("--delete defaults to false")
    func deleteDefaultFalse() throws {
        let config = try DeployerConfiguration(arguments: [])
        #expect(config.delete == false)
    }

    // MARK: - Help flag (Requirement 3.25)

    @available(LambdaSwift 2.0, *)
    @Test("--help flag is detected")
    func helpFlag() throws {
        let config = try DeployerConfiguration(arguments: ["--help"])
        #expect(config.help == true)
    }

    @available(LambdaSwift 2.0, *)
    @Test("--help defaults to false")
    func helpDefaultFalse() throws {
        let config = try DeployerConfiguration(arguments: [])
        #expect(config.help == false)
    }

    // MARK: - Verbose flag

    @available(LambdaSwift 2.0, *)
    @Test("--verbose flag is detected")
    func verboseFlag() throws {
        let config = try DeployerConfiguration(arguments: ["--verbose"])
        #expect(config.verboseLogging == true)
    }

    @available(LambdaSwift 2.0, *)
    @Test("--verbose defaults to false")
    func verboseDefaultFalse() throws {
        let config = try DeployerConfiguration(arguments: [])
        #expect(config.verboseLogging == false)
    }

    // MARK: - Products parsing

    @available(LambdaSwift 2.0, *)
    @Test("Products are parsed from arguments")
    func productsParsing() throws {
        let config = try DeployerConfiguration(arguments: ["--products", "MyLambda"])
        #expect(config.products == ["MyLambda"])
    }

    @available(LambdaSwift 2.0, *)
    @Test("Multiple comma-separated products are parsed")
    func multipleProductsParsing() throws {
        let config = try DeployerConfiguration(arguments: ["--products", "FuncA,FuncB,FuncC"])
        #expect(config.products == ["FuncA", "FuncB", "FuncC"])
    }

    @available(LambdaSwift 2.0, *)
    @Test("Products default to empty array")
    func productsDefaultEmpty() throws {
        let config = try DeployerConfiguration(arguments: [])
        #expect(config.products.isEmpty)
    }

    // MARK: - Profile parsing

    @available(LambdaSwift 2.0, *)
    @Test("Profile is parsed from arguments")
    func profileParsing() throws {
        let config = try DeployerConfiguration(arguments: ["--profile", "staging"])
        #expect(config.profile == "staging")
    }

    @available(LambdaSwift 2.0, *)
    @Test("Profile is nil when not specified")
    func profileDefaultNil() throws {
        let config = try DeployerConfiguration(arguments: [])
        #expect(config.profile == nil)
    }

    // MARK: - Combined arguments

    @available(LambdaSwift 2.0, *)
    @Test("Multiple options parsed together")
    func combinedArguments() throws {
        let config = try DeployerConfiguration(arguments: [
            "--region", "ap-southeast-1",
            "--architecture", "arm64",
            "--with-url",
            "--verbose",
            "--iam-role", "arn:aws:iam::123456789012:role/test",
            "--input-directory", "/tmp/output",
            "--products", "MyFunc",
        ])
        #expect(config.region == "ap-southeast-1")
        #expect(config.architecture == .arm64)
        #expect(config.withURL == true)
        #expect(config.verboseLogging == true)
        #expect(config.iamRole == "arn:aws:iam::123456789012:role/test")
        #expect(config.inputDirectory?.path().contains("/tmp/output") == true)
        #expect(config.products == ["MyFunc"])
    }

    @available(LambdaSwift 2.0, *)
    @Test("Delete with region and products")
    func deleteWithOptions() throws {
        let config = try DeployerConfiguration(arguments: [
            "--delete",
            "--region", "us-east-1",
            "--products", "MyFunc",
        ])
        #expect(config.delete == true)
        #expect(config.region == "us-east-1")
        #expect(config.products == ["MyFunc"])
    }
}
