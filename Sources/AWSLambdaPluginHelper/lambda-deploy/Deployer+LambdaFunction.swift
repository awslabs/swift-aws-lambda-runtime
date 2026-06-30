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
    // MARK: - Function Orchestration

    /// Maps the deployer architecture enum to the Lambda API architecture enum.
    static func lambdaArchitecture(
        from architecture: DeployerConfiguration.Architecture
    ) -> Lambda.Architecture {
        switch architecture {
        case .x64: return .x8664
        case .arm64: return .arm64
        }
    }

    /// Determines the upload strategy based on archive size.
    /// - Parameter archiveSize: The size of the ZIP archive in bytes.
    /// - Returns: `true` if the archive should be uploaded directly (base64), `false` if S3 staging is required.
    static func shouldUploadDirectly(archiveSize: Int64) -> Bool {
        archiveSize <= directUploadLimit
    }

    /// Creates a new Lambda function from a ZIP archive or a container image.
    ///
    /// Exactly one code source is provided: `zipData` (direct base64 upload), an S3
    /// `bucket`/`key` reference (for archives over the direct-upload limit), or an `imageUri`
    /// (an ECR image reference). A ZIP function is created with the `provided.al2023` runtime and a
    /// `bootstrap` handler; an image function omits both (the image's `ENTRYPOINT` is the runtime).
    ///
    /// - Parameters:
    ///   - name: The Lambda function name.
    ///   - architecture: The target architecture (x64 or arm64).
    ///   - role: The IAM role ARN for the function's execution role.
    ///   - zipData: ZIP archive data for direct upload.
    ///   - bucket: The S3 bucket of the deployment package.
    ///   - key: The S3 key of the deployment package.
    ///   - imageUri: An ECR image reference (`<repo>@<digest>`); when set, an Image function is created.
    ///   - lambdaClient: The Lambda client to use for the API call.
    ///   - verbose: Whether to emit verbose progress output.
    /// - Returns: The created function's configuration, including the function ARN.
    @discardableResult
    func createFunction(
        name: String,
        architecture: DeployerConfiguration.Architecture,
        role: String,
        zipData: Data? = nil,
        bucket: String? = nil,
        key: String? = nil,
        imageUri: String? = nil,
        using lambdaClient: Lambda,
        verbose: Bool
    ) async throws -> Lambda.FunctionConfiguration {
        if verbose {
            if let imageUri {
                print("[verbose] Creating Lambda function '\(name)' from image \(imageUri)...")
            } else if zipData != nil {
                let sizeMB = Double(zipData!.count) / (1024 * 1024)
                print(
                    "[verbose] Creating Lambda function '\(name)' with direct upload (\(String(format: "%.1f", sizeMB)) MB)..."
                )
            } else {
                print(
                    "[verbose] Creating Lambda function '\(name)' with S3 reference s3://\(bucket ?? "")/\(key ?? "")..."
                )
            }
        }

        // Build the request: an Image function omits runtime/handler; a ZIP function carries the
        // provided.al2023 runtime and a `bootstrap` handler with ZIP-or-S3 code.
        let request: Lambda.CreateFunctionRequest
        if let imageUri {
            request = Lambda.CreateFunctionRequest(
                architectures: [Self.lambdaArchitecture(from: architecture)],
                code: Lambda.FunctionCode(imageUri: imageUri),
                functionName: name,
                packageType: .image,
                role: role
            )
        } else {
            let code: Lambda.FunctionCode
            if let zipData {
                code = Lambda.FunctionCode(zipFile: .data(zipData))
            } else {
                code = Lambda.FunctionCode(s3Bucket: bucket, s3Key: key)
            }
            request = Lambda.CreateFunctionRequest(
                architectures: [Self.lambdaArchitecture(from: architecture)],
                code: code,
                functionName: name,
                handler: "bootstrap",
                packageType: .zip,
                role: role,
                runtime: .providedal2023
            )
        }

        // A just-created IAM role is not always assumable by Lambda immediately: IAM is eventually
        // consistent, so CreateFunction can fail with InvalidParameterValueException ("The role
        // defined for the function cannot be assumed by Lambda") until the role propagates.
        //
        // Role propagation is a fixed-time event (typically a few seconds), not an overloaded
        // dependency, so we poll quickly with a low delay ceiling rather than letting the default
        // exponential backoff grow coarse: that catches readiness within ~1s of it happening instead
        // of overshooting into long late-stage waits. The high attempt count keeps a generous ceiling
        // as a safety net.
        do {
            let response = try await withRetry(
                maxAttempts: 15,
                initialDelay: .milliseconds(500),
                maxDelay: .seconds(2),
                isRetryable: { self.isRoleNotYetAssumable($0) },
                onRetry: { attempt, _ in
                    if verbose {
                        print(
                            "[verbose] IAM role not yet assumable by Lambda (attempt \(attempt)/15); retrying..."
                        )
                    } else {
                        print("Waiting for the role (\(attempt)/15)...")
                    }
                },
                operation: {
                    try await lambdaClient.createFunction(request)
                }
            )
            if verbose {
                print("[verbose] Lambda function '\(name)' created successfully")
                if let arn = response.functionArn {
                    print("[verbose] Function ARN: \(arn)")
                }
            }
            return response
        } catch let error as LambdaErrorType {
            throw DeployerErrors.awsAPIError(
                service: "Lambda",
                operation: "CreateFunction",
                message: error.context?.message ?? error.errorCode
            )
        }
    }

    /// Whether a CreateFunction error indicates the execution role has not yet propagated and is
    /// therefore not yet assumable by Lambda — a transient, eventually-consistent IAM condition that
    /// is worth retrying.
    func isRoleNotYetAssumable(_ error: any Error) -> Bool {
        guard let error = error as? LambdaErrorType else { return false }
        return self.isRoleNotYetAssumable(errorCode: error.errorCode, message: error.message)
    }

    /// String-level predicate behind ``isRoleNotYetAssumable(_:)``, split out so it can be unit
    /// tested without constructing a `LambdaErrorType` (whose error context is not publicly
    /// constructible).
    func isRoleNotYetAssumable(errorCode: String, message: String?) -> Bool {
        errorCode == "InvalidParameterValueException"
            && (message?.contains("cannot be assumed by Lambda") ?? false)
    }

    /// Updates an existing Lambda function's code.
    ///
    /// The function code is provided either as a base64-encoded ZIP payload (direct upload)
    /// or as an S3 bucket/key reference (for archives exceeding the direct upload limit).
    ///
    /// - Parameters:
    ///   - name: The Lambda function name.
    ///   - zipData: ZIP archive data for direct upload.
    ///   - bucket: The S3 bucket of the deployment package.
    ///   - key: The S3 key of the deployment package.
    ///   - imageUri: An ECR image reference (`<repo>@<digest>`) for an Image function.
    ///   - lambdaClient: The Lambda client to use for the API call.
    ///   - verbose: Whether to emit verbose progress output.
    /// - Returns: The updated function's configuration.
    @discardableResult
    func updateFunctionCode(
        name: String,
        zipData: Data? = nil,
        bucket: String? = nil,
        key: String? = nil,
        imageUri: String? = nil,
        using lambdaClient: Lambda,
        verbose: Bool
    ) async throws -> Lambda.FunctionConfiguration {
        if verbose {
            if let imageUri {
                print("[verbose] Updating function code for '\(name)' to image \(imageUri)...")
            } else if zipData != nil {
                let sizeMB = Double(zipData!.count) / (1024 * 1024)
                print(
                    "[verbose] Updating function code for '\(name)' with direct upload (\(String(format: "%.1f", sizeMB)) MB)..."
                )
            } else {
                print(
                    "[verbose] Updating function code for '\(name)' with S3 reference s3://\(bucket ?? "")/\(key ?? "")..."
                )
            }
        }

        let request: Lambda.UpdateFunctionCodeRequest
        if let imageUri {
            request = Lambda.UpdateFunctionCodeRequest(functionName: name, imageUri: imageUri)
        } else if let zipData {
            request = Lambda.UpdateFunctionCodeRequest(functionName: name, zipFile: .data(zipData))
        } else {
            request = Lambda.UpdateFunctionCodeRequest(functionName: name, s3Bucket: bucket, s3Key: key)
        }

        do {
            let response = try await lambdaClient.updateFunctionCode(request)
            if verbose {
                print("[verbose] Function code for '\(name)' updated successfully")
                if let arn = response.functionArn {
                    print("[verbose] Function ARN: \(arn)")
                }
            }
            return response
        } catch let error as LambdaErrorType {
            throw DeployerErrors.awsAPIError(
                service: "Lambda",
                operation: "UpdateFunctionCode",
                message: error.context?.message ?? error.errorCode
            )
        }
    }

    /// Deletes a Lambda function and its associated IAM role.
    ///
    /// This first deletes the Lambda function using the DeleteFunction API,
    /// then cleans up the IAM role and its attached policies.
    ///
    /// - Parameters:
    ///   - name: The Lambda function name.
    ///   - lambdaClient: The Lambda client to use for the API call.
    ///   - iamClient: The IAM client to use for role cleanup.
    ///   - verbose: Whether to emit verbose progress output.
    func deleteFunction(
        name: String,
        using lambdaClient: Lambda,
        iamClient: IAM,
        verbose: Bool
    ) async throws {
        if verbose {
            print("[verbose] Deleting Lambda function '\(name)'...")
        }

        // Delete the function URL config first (ignore errors if not configured)
        do {
            try await lambdaClient.deleteFunctionUrlConfig(
                Lambda.DeleteFunctionUrlConfigRequest(functionName: name)
            )
            if verbose {
                print("[verbose] Deleted Function URL configuration for '\(name)'")
            }
        } catch {
            if verbose {
                print("[verbose] No Function URL to delete (or already deleted)")
            }
        }

        // Delete the Lambda function
        let request = Lambda.DeleteFunctionRequest(functionName: name)
        do {
            _ = try await lambdaClient.deleteFunction(request)
            if verbose {
                print("[verbose] Lambda function '\(name)' deleted successfully")
            }
        } catch let error as LambdaErrorType {
            throw DeployerErrors.awsAPIError(
                service: "Lambda",
                operation: "DeleteFunction",
                message: error.context?.message ?? error.errorCode
            )
        }

        print("Deleted Lambda function '\(name)'")

        // Delete the associated IAM role and its policies
        try await deleteIAMRole(functionName: name, using: iamClient, verbose: verbose)
    }
}
