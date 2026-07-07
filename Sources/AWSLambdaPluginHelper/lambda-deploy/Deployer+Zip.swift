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
import Logging
import SotoCore

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@available(LambdaSwift 2.0, *)
extension Deployer {
    // MARK: - ZIP deploy

    /// Deploys a ZIP artifact (create or update), returning the function ARN.
    ///
    /// Resolves the archive produced by `lambda-build`, uploads it directly when under the
    /// direct-upload limit or stages it through S3 otherwise, then creates or updates the function.
    /// The image counterpart is ``deployImage(functionName:manifest:action:accountId:region:configuration:existingConfiguration:awsClient:lambdaClient:iamClient:)``.
    func deployZip(
        functionName: String,
        architecture: DeployerConfiguration.Architecture,
        action: DeploymentAction,
        accountId: String,
        region: Region,
        configuration: DeployerConfiguration,
        existingConfiguration: Lambda.FunctionConfiguration?,
        lambdaClient: Lambda,
        iamClient: IAM,
        s3Client: S3
    ) async throws -> String? {
        // Resolve the ZIP archive path
        let archiveURL: URL
        if let inputDir = configuration.inputDirectory {
            archiveURL = inputDir.appendingPathComponent("\(functionName)/\(functionName).zip")
        } else {
            // Default build output path.
            // Check both the current Builder plugin path and the legacy Packager plugin path.
            // The legacy AWSLambdaPackager path can be removed when the archive plugin is retired.
            let builderPath = URL(
                fileURLWithPath:
                    ".build/plugins/AWSLambdaBuilder/outputs/AWSLambdaBuilder/\(functionName)/\(functionName).zip"
            )
            let packagerPath = URL(
                fileURLWithPath:
                    ".build/plugins/AWSLambdaPackager/outputs/AWSLambdaPackager/\(functionName)/\(functionName).zip"
            )

            if FileManager.default.fileExists(atPath: builderPath.path) {
                archiveURL = builderPath
            } else {
                // Fallback to legacy packager path (used by `swift package archive`)
                // TODO: remove this fallback when the AWSLambdaPackager plugin is retired
                archiveURL = packagerPath
            }
        }

        guard FileManager.default.fileExists(atPath: archiveURL.path) else {
            throw DeployerErrors.archiveNotFound(archiveURL)
        }

        let zipData = try Data(contentsOf: archiveURL)
        let archiveSize = Int64(zipData.count)

        if configuration.verboseLogging {
            let sizeMB = Double(archiveSize) / (1024 * 1024)
            print("[verbose] Archive: \(archiveURL.path) (\(Self.oneDecimal(sizeMB)) MB)")
            print(
                "[verbose] Upload strategy: \(Self.shouldUploadDirectly(archiveSize: archiveSize) ? "direct" : "S3 staging")"
            )
        }

        // Determine upload strategy
        var s3Bucket: String? = nil
        var s3Key: String? = nil

        if !Self.shouldUploadDirectly(archiveSize: archiveSize) {
            // Stage to S3
            print("Archive exceeds 50 MB, staging to S3...")
            let bucketName = Self.deploymentBucketName(region: region.rawValue, accountId: accountId)
            s3Key = "\(functionName)/\(functionName).zip"
            try await ensureBucketExists(
                bucket: bucketName,
                region: region,
                using: s3Client,
                verbose: configuration.verboseLogging
            )
            try await uploadToS3(
                bucket: bucketName,
                key: s3Key!,
                data: zipData,
                using: s3Client,
                verbose: configuration.verboseLogging
            )
            s3Bucket = bucketName
        }

        let functionArn: String?

        if action == .create {
            // Resolve IAM role
            print("Resolving IAM role...")
            let roleArn = try await resolveIAMRole(
                functionName: functionName,
                iamRole: configuration.iamRole,
                using: iamClient,
                verbose: configuration.verboseLogging
            )

            // Create the function
            print("Creating Lambda function '\(functionName)'...")
            let response: Lambda.FunctionConfiguration
            if let bucket = s3Bucket, let key = s3Key {
                response = try await createFunction(
                    name: functionName,
                    architecture: architecture,
                    role: roleArn,
                    bucket: bucket,
                    key: key,
                    using: lambdaClient,
                    verbose: configuration.verboseLogging
                )
            } else {
                response = try await createFunction(
                    name: functionName,
                    architecture: architecture,
                    role: roleArn,
                    zipData: zipData,
                    using: lambdaClient,
                    verbose: configuration.verboseLogging
                )
            }
            functionArn = response.functionArn
        } else {
            // Verify the function's execution role still exists before updating.
            // Lambda validates the role lazily (at invoke time), so an update against a
            // function whose role was deleted would succeed here but fail at invoke.
            // Reuse the configuration fetched during the existence check above.
            try await verifyExecutionRoleExists(
                roleARN: existingConfiguration?.role,
                functionName: functionName,
                using: iamClient,
                verbose: configuration.verboseLogging
            )

            // Update the function code
            print("Updating Lambda function '\(functionName)'...")
            let response: Lambda.FunctionConfiguration
            if let bucket = s3Bucket, let key = s3Key {
                response = try await updateFunctionCode(
                    name: functionName,
                    bucket: bucket,
                    key: key,
                    using: lambdaClient,
                    verbose: configuration.verboseLogging
                )
            } else {
                response = try await updateFunctionCode(
                    name: functionName,
                    zipData: zipData,
                    using: lambdaClient,
                    verbose: configuration.verboseLogging
                )
            }
            functionArn = response.functionArn
        }

        // Clean up S3 staged object
        if let bucket = s3Bucket, let key = s3Key {
            try await deleteFromS3(
                bucket: bucket,
                key: key,
                using: s3Client,
                verbose: configuration.verboseLogging
            )
        }

        return functionArn
    }
}
