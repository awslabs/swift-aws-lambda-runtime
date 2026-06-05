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

// MARK: - Deployment Bucket Name Construction Tests

@Suite("Deployment bucket name construction")
struct DeploymentBucketNameTests {

    @available(LambdaSwift 2.0, *)
    @Test("Bucket name has correct format: swift-aws-lambda-runtime-<region>-<accountId>")
    func bucketNameFormat() {
        let name = Deployer.deploymentBucketName(region: "us-east-1", accountId: "123456789012")
        #expect(name == "swift-aws-lambda-runtime-us-east-1-123456789012")
    }

    @available(LambdaSwift 2.0, *)
    @Test("Bucket name with eu-west-1 region")
    func bucketNameEuWest1() {
        let name = Deployer.deploymentBucketName(region: "eu-west-1", accountId: "987654321098")
        #expect(name == "swift-aws-lambda-runtime-eu-west-1-987654321098")
    }

    @available(LambdaSwift 2.0, *)
    @Test("Bucket name with ap-southeast-2 region")
    func bucketNameApSoutheast2() {
        let name = Deployer.deploymentBucketName(region: "ap-southeast-2", accountId: "111222333444")
        #expect(name == "swift-aws-lambda-runtime-ap-southeast-2-111222333444")
    }

    @available(LambdaSwift 2.0, *)
    @Test("Bucket name with us-west-2 region and different account")
    func bucketNameUsWest2() {
        let name = Deployer.deploymentBucketName(region: "us-west-2", accountId: "000000000000")
        #expect(name == "swift-aws-lambda-runtime-us-west-2-000000000000")
    }

    @available(LambdaSwift 2.0, *)
    @Test("Bucket name is always lowercase")
    func bucketNameIsLowercase() {
        let name = Deployer.deploymentBucketName(region: "us-east-1", accountId: "123456789012")
        #expect(name == name.lowercased())
    }

    @available(LambdaSwift 2.0, *)
    @Test(
        "Bucket name length is between 3 and 63 characters (valid S3 name)",
        arguments: [
            ("us-east-1", "123456789012"),
            ("eu-west-1", "987654321098"),
            ("ap-southeast-2", "111222333444"),
            ("us-gov-west-1", "555666777888"),
            ("me-south-1", "000000000001"),
        ]
    )
    func bucketNameLengthIsValid(region: String, accountId: String) {
        let name = Deployer.deploymentBucketName(region: region, accountId: accountId)
        #expect(name.count >= 3, "Bucket name must be at least 3 characters")
        #expect(name.count <= 63, "Bucket name must be at most 63 characters")
    }

    @available(LambdaSwift 2.0, *)
    @Test(
        "Bucket name contains only valid S3 characters (lowercase, digits, hyphens)",
        arguments: [
            ("us-east-1", "123456789012"),
            ("ap-northeast-1", "999888777666"),
            ("eu-central-1", "012345678901"),
        ]
    )
    func bucketNameContainsOnlyValidCharacters(region: String, accountId: String) {
        let name = Deployer.deploymentBucketName(region: region, accountId: accountId)
        let validCharacters = "abcdefghijklmnopqrstuvwxyz0123456789-"
        let allValid = name.allSatisfy { validCharacters.contains($0) }
        #expect(allValid, "Bucket name must contain only lowercase letters, digits, and hyphens")
    }
}

// MARK: - Archive Size Threshold Tests

@Suite("Archive size threshold and upload strategy")
struct ArchiveSizeThresholdTests {

    @available(LambdaSwift 2.0, *)
    @Test("directUploadLimit is exactly 50 MB")
    func directUploadLimitValue() {
        let expectedLimit: Int64 = 50 * 1024 * 1024
        #expect(Deployer.directUploadLimit == expectedLimit)
    }

    @available(LambdaSwift 2.0, *)
    @Test("Archive of exactly 50 MB should upload directly")
    func exactly50MBUploadsDirectly() {
        let fiftyMB: Int64 = 50 * 1024 * 1024
        #expect(Deployer.shouldUploadDirectly(archiveSize: fiftyMB) == true)
    }

    @available(LambdaSwift 2.0, *)
    @Test("Archive of 50 MB + 1 byte should use S3 staging")
    func fiftyMBPlusOneUsesS3() {
        let fiftyMBPlusOne: Int64 = 50 * 1024 * 1024 + 1
        #expect(Deployer.shouldUploadDirectly(archiveSize: fiftyMBPlusOne) == false)
    }

    @available(LambdaSwift 2.0, *)
    @Test("Archive of 0 bytes should upload directly")
    func zeroBytesUploadsDirectly() {
        #expect(Deployer.shouldUploadDirectly(archiveSize: 0) == true)
    }

    @available(LambdaSwift 2.0, *)
    @Test("Archive of 1 byte should upload directly")
    func oneByteUploadsDirectly() {
        #expect(Deployer.shouldUploadDirectly(archiveSize: 1) == true)
    }

    @available(LambdaSwift 2.0, *)
    @Test("Archive of 49 MB should upload directly")
    func fortyNineMBUploadsDirectly() {
        let fortyNineMB: Int64 = 49 * 1024 * 1024
        #expect(Deployer.shouldUploadDirectly(archiveSize: fortyNineMB) == true)
    }

    @available(LambdaSwift 2.0, *)
    @Test("Archive of 51 MB should use S3 staging")
    func fiftyOneMBUsesS3() {
        let fiftyOneMB: Int64 = 51 * 1024 * 1024
        #expect(Deployer.shouldUploadDirectly(archiveSize: fiftyOneMB) == false)
    }

    @available(LambdaSwift 2.0, *)
    @Test("Archive of 100 MB should use S3 staging")
    func hundredMBUsesS3() {
        let hundredMB: Int64 = 100 * 1024 * 1024
        #expect(Deployer.shouldUploadDirectly(archiveSize: hundredMB) == false)
    }

    @available(LambdaSwift 2.0, *)
    @Test("Archive of 250 MB (Lambda max) should use S3 staging")
    func lambdaMaxSizeUsesS3() {
        let lambdaMax: Int64 = 250 * 1024 * 1024
        #expect(Deployer.shouldUploadDirectly(archiveSize: lambdaMax) == false)
    }
}
