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
    // MARK: - S3 Staging

    /// AWS Lambda direct upload limit (50 MB compressed).
    /// Archives larger than this must be staged through S3.
    static let directUploadLimit: Int64 = 50 * 1024 * 1024

    /// Constructs the deployment bucket name per the naming convention.
    /// Format: `swift-aws-lambda-runtime-<region>-<accountId>`
    static func deploymentBucketName(region: String, accountId: String) -> String {
        "swift-aws-lambda-runtime-\(region)-\(accountId)"
    }

    /// Ensures the S3 deployment bucket exists. If the bucket does not exist, it is created.
    /// - Parameters:
    ///   - bucket: The bucket name.
    ///   - region: The AWS region for the bucket.
    ///   - s3Client: The S3 client to use.
    ///   - verbose: Whether to emit verbose progress output.
    func ensureBucketExists(bucket: String, region: Region, using s3Client: S3, verbose: Bool) async throws {
        if verbose {
            print("[verbose] Checking if deployment bucket '\(bucket)' exists...")
        }

        do {
            _ = try await s3Client.headBucket(S3.HeadBucketRequest(bucket: bucket))
            if verbose {
                print("[verbose] Deployment bucket '\(bucket)' exists")
            }
        } catch let error as S3ErrorType where error.context?.responseCode == .notFound {
            // Bucket does not exist, create it
            try await createBucket(bucket: bucket, region: region, using: s3Client, verbose: verbose)
        } catch let error as AWSResponseError where error.context?.responseCode == .notFound {
            // Bucket does not exist (fallback for unrecognized error codes)
            try await createBucket(bucket: bucket, region: region, using: s3Client, verbose: verbose)
        } catch let error as AWSRawError where error.context.responseCode == .notFound {
            // Bucket does not exist (fallback for HEAD responses with no body)
            try await createBucket(bucket: bucket, region: region, using: s3Client, verbose: verbose)
        }
    }

    /// Creates an S3 bucket. Includes `LocationConstraint` when the region is not `us-east-1`.
    private func createBucket(bucket: String, region: Region, using s3Client: S3, verbose: Bool) async throws {
        if verbose {
            print("[verbose] Creating deployment bucket '\(bucket)' in region '\(region.rawValue)'...")
        }

        let request: S3.CreateBucketRequest
        if region == .useast1 {
            request = S3.CreateBucketRequest(bucket: bucket)
        } else {
            let locationConstraint = S3.CreateBucketConfiguration(
                locationConstraint: S3.BucketLocationConstraint(rawValue: region.rawValue)
            )
            request = S3.CreateBucketRequest(bucket: bucket, createBucketConfiguration: locationConstraint)
        }

        do {
            _ = try await s3Client.createBucket(request)
            if verbose {
                print("[verbose] Deployment bucket '\(bucket)' created successfully")
            }
        } catch let error as S3ErrorType {
            throw DeployerErrors.awsAPIError(
                service: "S3",
                operation: "CreateBucket",
                message: error.context?.message ?? error.errorCode
            )
        }
    }

    /// Uploads a ZIP archive to S3 for deployment staging.
    /// - Parameters:
    ///   - bucket: The bucket to upload to.
    ///   - key: The object key.
    ///   - data: The ZIP archive data.
    ///   - s3Client: The S3 client to use.
    ///   - verbose: Whether to emit verbose progress output.
    func uploadToS3(bucket: String, key: String, data: Data, using s3Client: S3, verbose: Bool) async throws {
        if verbose {
            let sizeMB = Double(data.count) / (1024 * 1024)
            print("[verbose] Uploading archive to s3://\(bucket)/\(key) (\(String(format: "%.1f", sizeMB)) MB)...")
        }

        let request = S3.PutObjectRequest(body: AWSHTTPBody(bytes: data), bucket: bucket, key: key)

        do {
            _ = try await s3Client.putObject(request)
            if verbose {
                print("[verbose] Upload to S3 completed successfully")
            }
        } catch let error as S3ErrorType {
            throw DeployerErrors.awsAPIError(
                service: "S3",
                operation: "PutObject",
                message: error.context?.message ?? error.errorCode
            )
        }
    }

    /// Deletes a staged S3 object after deployment completes.
    /// The bucket is retained for reuse by future deployments.
    /// - Parameters:
    ///   - bucket: The bucket containing the object.
    ///   - key: The object key to delete.
    ///   - s3Client: The S3 client to use.
    ///   - verbose: Whether to emit verbose progress output.
    func deleteFromS3(bucket: String, key: String, using s3Client: S3, verbose: Bool) async throws {
        if verbose {
            print("[verbose] Cleaning up staged object s3://\(bucket)/\(key)...")
        }

        let request = S3.DeleteObjectRequest(bucket: bucket, key: key)

        do {
            _ = try await s3Client.deleteObject(request)
            if verbose {
                print("[verbose] Staged object deleted successfully")
            }
        } catch let error as S3ErrorType {
            throw DeployerErrors.awsAPIError(
                service: "S3",
                operation: "DeleteObject",
                message: error.context?.message ?? error.errorCode
            )
        }
    }
}
