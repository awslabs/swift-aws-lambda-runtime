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

// MARK: - Property 2: Deprecated option alias equivalence

/// **Validates: Requirements 7.5, 7.6**
///
/// For any path value, `--output-directory <path>` produces the same `outputDirectory`
/// as `--output-path <path>`.
@Suite("Property 2: Deprecated option alias equivalence")
struct DeprecatedAliasEquivalencePropertyTests {

    static let samplePaths: [String] = [
        "/tmp/output",
        "/usr/local/build",
        "/home/user/projects/my-lambda/output",
        "/var/folders/abc/xyz",
        "/a",
        "/output-with-dashes",
        "/path/with spaces",
        "/path_with_underscores/nested/deep/dir",
        "/simple",
        "/very/long/path/that/goes/deep/into/the/filesystem/structure/for/testing",
        "/tmp",
        "/usr",
        "/build",
        "/opt/lambda/out",
        "/Users/developer/Desktop/project/dist",
        "/root/deploy",
        "/mnt/data/builds/release",
        "/srv/app/output",
        "/home/ci/workspace/artifacts",
        "/tmp/swift-build-output",
        "/Volumes/External/builds",
        "/private/tmp/xcode-build",
        "/workspace/output",
        "/code/bin",
        "/artifacts/v1.0",
        "/release/arm64",
        "/debug/output",
        "/home/user/.build/output",
        "/tmp/output-2024",
        "/project/dist/lambda",
        "/builds/nightly/latest",
        "/ci/artifacts/staging",
        "/deploy/packages",
        "/lambda/archives",
        "/swift/build/products",
        "/output123",
        "/tmp/a/b/c/d/e/f/g",
        "/data/out",
        "/results/final",
        "/packages/compiled",
        "/snapshots/build-42",
        "/Users/test/output",
        "/tmp/build-output-1",
        "/tmp/build-output-2",
        "/tmp/build-output-3",
        "/var/output/lambda",
        "/opt/builds/release-2",
        "/srv/builds/debug-1",
        "/home/dev/out",
        "/workspace/dist",
        "/project/target",
        "/builds/latest",
        "/artifacts/snapshot",
        "/deploy/staging",
        "/lambda/output",
        "/archive/dir",
        "/compiled/bins",
        "/packaged/zips",
        "/release/packages",
        "/debug/bins",
        "/test/output",
        "/ci/output",
        "/cd/output",
        "/dev/output",
        "/staging/output",
        "/prod/output",
        "/alpha/output",
        "/beta/output",
        "/gamma/output",
        "/delta/output",
        "/epsilon/output",
        "/zeta/output",
        "/eta/output",
        "/theta/output",
        "/iota/output",
        "/kappa/output",
        "/lambda-out",
        "/mu/output",
        "/nu/output",
        "/xi/output",
        "/omicron/output",
        "/pi/output",
        "/rho/output",
        "/sigma/output",
        "/tau/output",
        "/upsilon/output",
        "/phi/output",
        "/chi/output",
        "/psi/output",
        "/omega/output",
        "/final/output",
        "/last/output",
        "/end/output",
        "/done/output",
        "/complete/output",
        "/finished/output",
        "/ready/output",
        "/built/output",
        "/assembled/output",
        "/crafted/output",
        "/forged/output",
        "/made/output",
        "/created/output",
        "/generated/output",
        "/produced/output",
    ]

    private func baseArgs(excludingOutputArgs: Bool = true) -> [String] {
        [
            "--package-id", "my-package",
            "--package-display-name", "MyPackage",
            "--package-directory", "/tmp/project",
            "--docker-tool-path", "/usr/local/bin/docker",
            "--zip-tool-path", "/usr/bin/zip",
            "--products", "MyLambda",
            "--configuration", "release",
        ]
    }

    @available(LambdaSwift 2.0, *)
    @Test("--output-directory produces same outputDirectory as --output-path", arguments: samplePaths)
    func deprecatedAliasEquivalence(path: String) throws {
        let argsWithOutputPath = baseArgs() + ["--output-path", path]
        let configWithOutputPath = try BuilderConfiguration(arguments: argsWithOutputPath)

        let argsWithOutputDirectory = baseArgs() + ["--output-directory", path]
        let configWithOutputDirectory = try BuilderConfiguration(arguments: argsWithOutputDirectory)

        #expect(
            configWithOutputPath.outputDirectory == configWithOutputDirectory.outputDirectory,
            "--output-directory '\(path)' should produce same outputDirectory as --output-path '\(path)'"
        )
    }
}

// MARK: - Property 3: Cross-compile method parsing round-trip

/// **Validates: Requirements 2.7**
///
/// For any valid `CrossCompileMethod` enum case, `rawValue` → parse → original case.
/// Note: swift-static-sdk and custom-sdk throw "unsupported" on `parse()`, but their
/// rawValue round-trips through the enum initializer correctly.
@Suite("Property 3: Cross-compile method parsing round-trip")
struct CrossCompileMethodRoundTripPropertyTests {

    @available(LambdaSwift 2.0, *)
    static var allCases: [CrossCompileMethod] {
        [
            .docker,
            .container,
            .swiftStaticSdk,
            .customSdk,
        ]
    }

    @available(LambdaSwift 2.0, *)
    @Test("rawValue → init(rawValue:) round-trips for all CrossCompileMethod cases", arguments: allCases)
    func rawValueRoundTrip(method: CrossCompileMethod) {
        let rawValue = method.rawValue
        let parsed = CrossCompileMethod(rawValue: rawValue)
        #expect(parsed == method, "CrossCompileMethod(rawValue: \"\(rawValue)\") should produce \(method)")
    }
}

// MARK: - Property 4: Mutual exclusion of --swift-version and --base-docker-image

/// **Validates: Requirements 2.17**
///
/// For any non-empty swift-version and any non-empty base-docker-image, parsing throws an error.
@Suite("Property 4: Mutual exclusion of --swift-version and --base-docker-image")
struct MutualExclusionPropertyTests {

    static let swiftVersions: [String] = [
        "5.9", "5.10", "6.0", "6.1", "6.2",
        "5.9.1", "5.9.2", "5.10.1", "6.0.1", "6.0.2",
        "6.1.0", "6.1.1", "6.2.0", "7.0", "8.0",
        "5.0", "5.1", "5.2", "5.3", "5.4",
        "5.5", "5.6", "5.7", "5.8", "4.2",
    ]

    static let dockerImages: [String] = [
        "swift:5.9-amazonlinux2023",
        "swift:6.0-amazonlinux2023",
        "swift:6.1-amazonlinux2023",
        "swift:latest-amazonlinux2023",
        "swift:5.10-amazonlinux2",
        "myregistry/swift:6.0-al2023",
        "custom-image:latest",
        "ubuntu:22.04",
        "swift:nightly-amazonlinux2023",
        "ghcr.io/swift/swift:6.0",
    ]

    static let combinations: [(String, String)] = {
        var result: [(String, String)] = []
        for version in swiftVersions {
            for image in dockerImages {
                result.append((version, image))
            }
        }
        // Return first 100
        return Array(result.prefix(100))
    }()

    private func baseArgs() -> [String] {
        [
            "--package-id", "my-package",
            "--package-display-name", "MyPackage",
            "--package-directory", "/tmp/project",
            "--docker-tool-path", "/usr/local/bin/docker",
            "--zip-tool-path", "/usr/bin/zip",
            "--output-path", "/tmp/output",
            "--products", "MyLambda",
            "--configuration", "release",
        ]
    }

    @available(LambdaSwift 2.0, *)
    @Test(
        "Both --swift-version and --base-docker-image throws error",
        arguments: combinations
    )
    func mutualExclusionThrows(version: String, image: String) {
        let args = baseArgs() + ["--swift-version", version, "--base-docker-image", image]
        #expect(throws: (any Error).self) {
            _ = try BuilderConfiguration(arguments: args)
        }
    }
}

// MARK: - Property 5: Deployment bucket name construction

/// **Validates: Requirements 3.17, 3.18**
///
/// For any valid region and 12-digit account ID, result matches
/// "swift-aws-lambda-runtime-<region>-<accountId>" and is a valid S3 bucket name.
@Suite("Property 5: Deployment bucket name construction")
struct DeploymentBucketNamePropertyTests {

    static let regions: [String] = [
        "us-east-1", "us-east-2", "us-west-1", "us-west-2",
        "eu-west-1", "eu-west-2", "eu-west-3", "eu-central-1", "eu-central-2",
        "eu-north-1", "eu-south-1", "eu-south-2",
        "ap-southeast-1", "ap-southeast-2", "ap-southeast-3", "ap-southeast-4",
        "ap-northeast-1", "ap-northeast-2", "ap-northeast-3",
        "ap-south-1", "ap-south-2", "ap-east-1",
        "sa-east-1", "ca-central-1", "ca-west-1",
        "me-south-1", "me-central-1",
        "af-south-1", "il-central-1",
        "us-gov-west-1", "us-gov-east-1",
    ]

    static let accountIds: [String] = [
        "123456789012", "000000000000", "999999999999",
        "111111111111", "222222222222", "333333333333",
        "444444444444", "555555555555", "666666666666",
        "777777777777", "888888888888", "012345678901",
        "109876543210", "100200300400", "001002003004",
    ]

    static let combinations: [(String, String)] = {
        var result: [(String, String)] = []
        for region in regions {
            for accountId in accountIds {
                result.append((region, accountId))
            }
        }
        // Return first 100
        return Array(result.prefix(100))
    }()

    @available(LambdaSwift 2.0, *)
    @Test(
        "Bucket name matches expected format and is a valid S3 name",
        arguments: combinations
    )
    func bucketNameConstruction(region: String, accountId: String) {
        let name = Deployer.deploymentBucketName(region: region, accountId: accountId)

        // Verify format
        let expectedName = "swift-aws-lambda-runtime-\(region)-\(accountId)"
        #expect(name == expectedName, "Expected '\(expectedName)' but got '\(name)'")

        // Verify it's lowercase
        #expect(name == name.lowercased(), "Bucket name must be all lowercase")

        // Verify length is between 3 and 63 characters (valid S3 bucket name)
        #expect(name.count >= 3, "Bucket name must be at least 3 characters, got \(name.count)")
        #expect(name.count <= 63, "Bucket name must be at most 63 characters, got \(name.count)")

        // Verify only valid S3 bucket name characters (lowercase letters, digits, hyphens)
        let validChars = "abcdefghijklmnopqrstuvwxyz0123456789-"
        let allValid = name.allSatisfy { validChars.contains($0) }
        #expect(allValid, "Bucket name must contain only lowercase letters, digits, and hyphens")

        // Verify doesn't start or end with hyphen
        #expect(!name.hasPrefix("-"), "Bucket name must not start with a hyphen")
        #expect(!name.hasSuffix("-"), "Bucket name must not end with a hyphen")
    }
}

// MARK: - Property 6: Archive size determines upload strategy

/// **Validates: Requirements 3.15, 3.19**
///
/// For any size ≤ 50 MB → direct upload; for any size > 50 MB → S3 staging.
@Suite("Property 6: Archive size determines upload strategy")
struct ArchiveSizeUploadStrategyPropertyTests {

    static let fiftyMB: Int64 = 50 * 1024 * 1024

    static let sizesAtOrBelowLimit: [Int64] = {
        var sizes: [Int64] = [0, 1, 100, 1024, 10_000, 100_000, 1_000_000]
        // Add sizes approaching the boundary
        let limit: Int64 = fiftyMB
        for offset: Int64 in stride(from: 50, through: 0, by: -1) {
            sizes.append(limit - offset)
        }
        // Add various sizes below limit
        let moreSizes: [Int64] = [
            Int64(1024 * 1024),
            Int64(5 * 1024 * 1024),
            Int64(10 * 1024 * 1024),
            Int64(20 * 1024 * 1024),
            Int64(25 * 1024 * 1024),
            Int64(30 * 1024 * 1024),
            Int64(40 * 1024 * 1024),
            Int64(45 * 1024 * 1024),
            Int64(49 * 1024 * 1024),
        ]
        sizes.append(contentsOf: moreSizes)
        return Array(Set(sizes).sorted().prefix(100))
    }()

    static let sizesAboveLimit: [Int64] = {
        var sizes: [Int64] = []
        let limit: Int64 = fiftyMB
        // Add sizes just above the boundary
        for offset: Int64 in 1...51 {
            sizes.append(limit + offset)
        }
        // Add various sizes above limit
        let moreSizes: [Int64] = [
            Int64(51 * 1024 * 1024),
            Int64(55 * 1024 * 1024),
            Int64(60 * 1024 * 1024),
            Int64(75 * 1024 * 1024),
            Int64(100 * 1024 * 1024),
            Int64(150 * 1024 * 1024),
            Int64(200 * 1024 * 1024),
            Int64(250 * 1024 * 1024),
            Int64(300 * 1024 * 1024),
            Int64(500 * 1024 * 1024),
            Int64(1024 * 1024 * 1024),
        ]
        sizes.append(contentsOf: moreSizes)
        return Array(Set(sizes).sorted().prefix(100))
    }()

    @available(LambdaSwift 2.0, *)
    @Test("Sizes at or below 50 MB should upload directly", arguments: sizesAtOrBelowLimit)
    func sizeAtOrBelowLimitUploadsDirect(size: Int64) {
        #expect(
            Deployer.shouldUploadDirectly(archiveSize: size) == true,
            "Archive of \(size) bytes (≤ 50 MB) should upload directly"
        )
    }

    @available(LambdaSwift 2.0, *)
    @Test("Sizes above 50 MB should use S3 staging", arguments: sizesAboveLimit)
    func sizeAboveLimitUsesS3(size: Int64) {
        #expect(
            Deployer.shouldUploadDirectly(archiveSize: size) == false,
            "Archive of \(size) bytes (> 50 MB) should use S3 staging"
        )
    }
}

// MARK: - Property 8: AL2 warning logic

/// **Validates: Requirements 6.2, 6.3**
///
/// For any image containing "amazonlinux2" but NOT "amazonlinux2023" → explicitAL2Image is true.
/// For "amazonlinux2023" or default → explicitAL2Image is false.
@Suite("Property 8: AL2 warning emitted only for explicit AL2 image selection")
struct AL2WarningLogicPropertyTests {

    static let al2Images: [String] = [
        "swift:5.9-amazonlinux2",
        "swift:5.10-amazonlinux2",
        "swift:6.0-amazonlinux2",
        "swift:6.1-amazonlinux2",
        "swift:latest-amazonlinux2",
        "myregistry/swift:5.9-amazonlinux2",
        "custom-amazonlinux2-image:v1",
        "swift:nightly-amazonlinux2",
        "ghcr.io/swift:6.0-amazonlinux2",
        "amazonlinux2-swift:6.0",
        "swift:5.8-amazonlinux2",
        "swift:5.7-amazonlinux2",
        "swift:5.6-amazonlinux2",
        "registry.example.com/swift:6.0-amazonlinux2",
        "my-amazonlinux2-build:latest",
        "swift-amazonlinux2:6.1",
        "public.ecr.aws/swift:6.0-amazonlinux2",
        "test-amazonlinux2-image",
        "swift:5.5-amazonlinux2",
        "dev-amazonlinux2:v2",
        "swift:5.4-amazonlinux2",
        "swift:5.3-amazonlinux2",
        "base-amazonlinux2:latest",
        "swift-runtime-amazonlinux2:6.0",
        "ci-amazonlinux2-builder:1.0",
        "swift:5.2-amazonlinux2",
        "custom-swift-amazonlinux2:dev",
        "swift:5.1-amazonlinux2",
        "staging-amazonlinux2:v3",
        "swift:5.0-amazonlinux2",
        "swift:4.2-amazonlinux2",
        "build-amazonlinux2:release",
        "swift:amazonlinux2",
        "my/repo/amazonlinux2:tag",
        "test:amazonlinux2-latest",
        "swift:6.2-amazonlinux2",
        "registry/amazonlinux2-swift:v1",
        "local-amazonlinux2:dev",
        "swift:nightly-main-amazonlinux2",
        "swift:6.0.1-amazonlinux2",
        "swift:6.0.2-amazonlinux2",
        "swift:6.1.0-amazonlinux2",
        "builder-amazonlinux2:prod",
        "deploy-amazonlinux2:staging",
        "lambda-amazonlinux2:latest",
        "swift-lambda-amazonlinux2:6.0",
        "amazonlinux2-builder:v4",
        "ci/cd-amazonlinux2:latest",
        "swift:release-amazonlinux2",
        "swift:dev-amazonlinux2",
    ]

    static let nonAL2Images: [String] = [
        "swift:5.9-amazonlinux2023",
        "swift:6.0-amazonlinux2023",
        "swift:6.1-amazonlinux2023",
        "swift:latest-amazonlinux2023",
        "swift:nightly-amazonlinux2023",
        "myregistry/swift:6.0-amazonlinux2023",
        "custom-amazonlinux2023:v1",
        "ubuntu:22.04",
        "debian:bookworm",
        "alpine:3.18",
        "fedora:39",
        "centos:stream9",
        "swift:6.0",
        "swift:latest",
        "ghcr.io/swift:6.0-amazonlinux2023",
        "registry.example.com/swift:6.0-amazonlinux2023",
        "public.ecr.aws/swift:6.0-amazonlinux2023",
        "swift:5.10-amazonlinux2023",
        "swift:6.2-amazonlinux2023",
        "custom-image:latest",
        "my-build-image:v1",
        "swift-builder:6.0",
        "lambda-base:latest",
        "ci-runner:2.0",
        "dev-env:latest",
        "swift:nightly-main-amazonlinux2023",
        "swift:6.0.1-amazonlinux2023",
        "swift:6.0.2-amazonlinux2023",
        "swift:6.1.0-amazonlinux2023",
        "amazonlinux2023-swift:6.0",
        "my-amazonlinux2023-image:v1",
        "swift-amazonlinux2023:latest",
        "ci-amazonlinux2023:prod",
        "builder-amazonlinux2023:v2",
        "deploy-amazonlinux2023:staging",
        "swift:release-amazonlinux2023",
        "swift:dev-amazonlinux2023",
        "registry/amazonlinux2023-swift:v1",
        "local-amazonlinux2023:dev",
        "staging-amazonlinux2023:v3",
        "base-amazonlinux2023:latest",
        "swift-runtime-amazonlinux2023:6.0",
        "ci-amazonlinux2023-builder:1.0",
        "lambda-amazonlinux2023:latest",
        "swift-lambda-amazonlinux2023:6.0",
        "amazonlinux2023-builder:v4",
        "test-amazonlinux2023-image",
        "prod-amazonlinux2023:release",
        "nightly-amazonlinux2023:latest",
        "snapshot-amazonlinux2023:v5",
    ]

    private func baseArgs() -> [String] {
        [
            "--package-id", "my-package",
            "--package-display-name", "MyPackage",
            "--package-directory", "/tmp/project",
            "--docker-tool-path", "/usr/local/bin/docker",
            "--zip-tool-path", "/usr/bin/zip",
            "--output-path", "/tmp/output",
            "--products", "MyLambda",
            "--configuration", "release",
        ]
    }

    @available(LambdaSwift 2.0, *)
    @Test("AL2 images (not AL2023) set explicitAL2Image to true", arguments: al2Images)
    func al2ImageDetected(image: String) throws {
        let args = baseArgs() + ["--base-docker-image", image]
        let config = try BuilderConfiguration(arguments: args)
        #expect(
            config.explicitAL2Image == true,
            "Image '\(image)' contains 'amazonlinux2' but not 'amazonlinux2023', should set explicitAL2Image=true"
        )
    }

    @available(LambdaSwift 2.0, *)
    @Test("AL2023 or non-AL2 images set explicitAL2Image to false", arguments: nonAL2Images)
    func nonAL2ImageNotDetected(image: String) throws {
        let args = baseArgs() + ["--base-docker-image", image]
        let config = try BuilderConfiguration(arguments: args)
        #expect(
            config.explicitAL2Image == false,
            "Image '\(image)' should set explicitAL2Image=false"
        )
    }

    @available(LambdaSwift 2.0, *)
    @Test("Default image (no --base-docker-image) sets explicitAL2Image to false")
    func defaultImageNotFlagged() throws {
        let args = baseArgs()
        let config = try BuilderConfiguration(arguments: args)
        #expect(config.explicitAL2Image == false)
    }
}

// MARK: - Property 9: Unsupported cross-compile methods report error with link

/// **Validates: Requirements 2.14**
///
/// For swift-static-sdk and custom-sdk, CrossCompileMethod.parse throws error
/// containing the SDK guide URL.
@Suite("Property 9: Unsupported cross-compile methods report error with link")
struct UnsupportedCrossCompileMethodsPropertyTests {

    static let unsupportedMethods: [String] = [
        "swift-static-sdk",
        "custom-sdk",
    ]

    static let sdkGuideURL = "https://www.swift.org/documentation/articles/static-linux-getting-started.html"

    @available(LambdaSwift 2.0, *)
    @Test("Unsupported methods throw error with SDK guide URL", arguments: unsupportedMethods)
    func unsupportedMethodThrowsWithLink(method: String) {
        do {
            _ = try CrossCompileMethod.parse(method)
            Issue.record("Expected CrossCompileMethod.parse(\"\(method)\") to throw, but it succeeded")
        } catch {
            let errorDescription = String(describing: error)
            #expect(
                errorDescription.contains(Self.sdkGuideURL),
                "Error for '\(method)' should contain SDK guide URL '\(Self.sdkGuideURL)', got: \(errorDescription)"
            )
        }
    }

    @available(LambdaSwift 2.0, *)
    @Test("Unsupported methods via BuilderConfiguration throw error with SDK guide URL", arguments: unsupportedMethods)
    func unsupportedMethodInBuilderConfigThrowsWithLink(method: String) {
        let args: [String] = [
            "--package-id", "my-package",
            "--package-display-name", "MyPackage",
            "--package-directory", "/tmp/project",
            "--docker-tool-path", "/usr/local/bin/docker",
            "--zip-tool-path", "/usr/bin/zip",
            "--output-path", "/tmp/output",
            "--products", "MyLambda",
            "--configuration", "release",
            "--cross-compile", method,
        ]
        do {
            _ = try BuilderConfiguration(arguments: args)
            Issue.record("Expected BuilderConfiguration to throw for --cross-compile \(method)")
        } catch {
            let errorDescription = String(describing: error)
            #expect(
                errorDescription.contains(Self.sdkGuideURL),
                "Error for '--cross-compile \(method)' should contain SDK guide URL, got: \(errorDescription)"
            )
        }
    }
}

@Suite("Property 10: Execution role name extraction from ARN")
struct ExecutionRoleARNParsingTests {

    static let validARNs: [(arn: String, expected: String)] = [
        ("arn:aws:iam::123456789012:role/swift-lambda-MyLambda-role", "swift-lambda-MyLambda-role"),
        ("arn:aws:iam::000000000000:role/basic", "basic"),
        ("arn:aws:iam::123456789012:role/service-role/my-service-role", "my-service-role"),
        ("arn:aws-us-gov:iam::123456789012:role/gov-role", "gov-role"),
        ("arn:aws:iam::123456789012:role/path/to/deeply/nested-role", "nested-role"),
    ]

    @available(LambdaSwift 2.0, *)
    @Test("Role name is the last path component of the ARN", arguments: validARNs)
    func extractsRoleName(arn: String, expected: String) {
        #expect(Deployer.roleName(fromARN: arn) == expected)
    }

    static let invalidARNs: [String] = [
        "",
        "not-an-arn",
        "arn:aws:iam::123456789012:role/",
    ]

    @available(LambdaSwift 2.0, *)
    @Test("ARNs without a role name return nil", arguments: invalidARNs)
    func returnsNilForInvalidARN(arn: String) {
        #expect(Deployer.roleName(fromARN: arn) == nil)
    }
}
