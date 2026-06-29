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
enum DeploymentAction: Equatable {
    /// Create a new function (function does not exist yet).
    case create
    /// Update an existing function's code.
    case update
    /// Delete an existing function.
    case delete
}

@available(LambdaSwift 2.0, *)
struct Deployer {

    // MARK: - Account ID and Function Existence

    /// Resolves the AWS account ID by calling STS GetCallerIdentity.
    func resolveAccountId(using stsClient: STSClient) async throws -> String {
        do {
            let response = try await stsClient.getCallerIdentity()
            guard let accountId = response.account else {
                throw DeployerErrors.credentialResolutionFailed(
                    "STS GetCallerIdentity returned no account ID"
                )
            }
            return accountId
        } catch let error as DeployerErrors {
            throw error
        } catch {
            throw DeployerErrors.awsAPIError(
                service: "STS",
                operation: "GetCallerIdentity",
                message: "\(error)"
            )
        }
    }

    /// Looks up an existing Lambda function's configuration.
    ///
    /// Returns the function's current configuration, or `nil` if no function with the given name
    /// exists. The configuration is carried downstream so callers (e.g. the update path) can reuse
    /// it — for example to validate the execution role — without issuing a second `GetFunction` call.
    func existingFunctionConfiguration(
        _ functionName: String,
        using lambdaClient: LambdaClient
    ) async throws -> FunctionConfiguration? {
        do {
            return try await lambdaClient.getFunction(
                GetFunctionRequest(functionName: functionName)
            ).configuration
        } catch {
            // If the error indicates the resource was not found, the function doesn't exist
            let errorDescription = "\(error)"
            if errorDescription.contains("ResourceNotFoundException")
                || errorDescription.contains("Function not found")
            {
                return nil
            }
            throw DeployerErrors.awsAPIError(
                service: "Lambda",
                operation: "GetFunction",
                message: errorDescription
            )
        }
    }

    /// Determines the deployment action based on function existence and the `--delete` flag.
    func determineDeploymentAction(
        functionExists: Bool,
        delete: Bool
    ) throws -> DeploymentAction {
        if delete {
            guard functionExists else {
                throw DeployerErrors.awsAPIError(
                    service: "Lambda",
                    operation: "DeleteFunction",
                    message: "cannot delete function: function does not exist"
                )
            }
            return .delete
        }
        return functionExists ? .update : .create
    }

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
    func ensureBucketExists(bucket: String, region: Region, using s3Client: S3Client, verbose: Bool) async throws {
        if verbose {
            print("[verbose] Checking if deployment bucket '\(bucket)' exists...")
        }

        do {
            try await s3Client.headBucket(HeadBucketRequest(bucket: bucket))
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
    private func createBucket(bucket: String, region: Region, using s3Client: S3Client, verbose: Bool) async throws {
        if verbose {
            print("[verbose] Creating deployment bucket '\(bucket)' in region '\(region.rawValue)'...")
        }

        let request: CreateBucketRequest
        if region == .useast1 {
            request = CreateBucketRequest(bucket: bucket)
        } else {
            let locationConstraint = CreateBucketConfiguration(locationConstraint: region.rawValue)
            request = CreateBucketRequest(bucket: bucket, createBucketConfiguration: locationConstraint)
        }

        do {
            try await s3Client.createBucket(request)
            if verbose {
                print("[verbose] Deployment bucket '\(bucket)' created successfully")
            }
        } catch let error as S3ErrorType {
            throw DeployerErrors.awsAPIError(
                service: "S3",
                operation: "CreateBucket",
                message: error.message ?? error.errorCode
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
    func uploadToS3(bucket: String, key: String, data: Data, using s3Client: S3Client, verbose: Bool) async throws {
        if verbose {
            let sizeMB = Double(data.count) / (1024 * 1024)
            print("[verbose] Uploading archive to s3://\(bucket)/\(key) (\(String(format: "%.1f", sizeMB)) MB)...")
        }

        let request = PutObjectRequest(bucket: bucket, key: key, body: AWSHTTPBody(bytes: data))

        do {
            try await s3Client.putObject(request)
            if verbose {
                print("[verbose] Upload to S3 completed successfully")
            }
        } catch let error as S3ErrorType {
            throw DeployerErrors.awsAPIError(
                service: "S3",
                operation: "PutObject",
                message: error.message ?? error.errorCode
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
    func deleteFromS3(bucket: String, key: String, using s3Client: S3Client, verbose: Bool) async throws {
        if verbose {
            print("[verbose] Cleaning up staged object s3://\(bucket)/\(key)...")
        }

        let request = DeleteObjectRequest(bucket: bucket, key: key)

        do {
            try await s3Client.deleteObject(request)
            if verbose {
                print("[verbose] Staged object deleted successfully")
            }
        } catch let error as S3ErrorType {
            throw DeployerErrors.awsAPIError(
                service: "S3",
                operation: "DeleteObject",
                message: error.message ?? error.errorCode
            )
        }
    }

    // MARK: - Function Orchestration

    /// Maps the deployer architecture enum to the Lambda API architecture enum.
    private static func lambdaArchitecture(
        from architecture: DeployerConfiguration.Architecture
    ) -> LambdaArchitecture {
        switch architecture {
        case .x64: return .x86_64
        case .arm64: return .arm64
        }
    }

    /// Determines the upload strategy based on archive size.
    /// - Parameter archiveSize: The size of the ZIP archive in bytes.
    /// - Returns: `true` if the archive should be uploaded directly (base64), `false` if S3 staging is required.
    static func shouldUploadDirectly(archiveSize: Int64) -> Bool {
        archiveSize <= directUploadLimit
    }

    /// Creates a new Lambda function with the `provided.al2023` runtime.
    ///
    /// The function code is provided either as a base64-encoded ZIP payload (direct upload)
    /// or as an S3 bucket/key reference (for archives exceeding the direct upload limit).
    ///
    /// - Parameters:
    ///   - name: The Lambda function name.
    ///   - architecture: The target architecture (x64 or arm64).
    ///   - role: The IAM role ARN for the function's execution role.
    ///   - zipData: The ZIP archive data for direct upload (mutually exclusive with bucket/key).
    ///   - bucket: The S3 bucket containing the deployment package (mutually exclusive with zipData).
    ///   - key: The S3 key of the deployment package (mutually exclusive with zipData).
    ///   - lambdaClient: The Lambda client to use for the API call.
    ///   - verbose: Whether to emit verbose progress output.
    /// - Returns: The response from the CreateFunction API including the function ARN.
    @discardableResult
    func createFunction(
        name: String,
        architecture: DeployerConfiguration.Architecture,
        role: String,
        zipData: Data? = nil,
        bucket: String? = nil,
        key: String? = nil,
        using lambdaClient: LambdaClient,
        verbose: Bool
    ) async throws -> CreateFunctionResponse {
        if verbose {
            if zipData != nil {
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

        // Build the function code — either direct ZIP or S3 reference
        let code: FunctionCode
        if let zipData {
            code = FunctionCode(zipFile: zipData.base64EncodedString())
        } else {
            code = FunctionCode(s3Bucket: bucket, s3Key: key)
        }

        let request = CreateFunctionRequest(
            functionName: name,
            role: role,
            runtime: .providedAl2023,
            handler: "bootstrap",
            code: code,
            architectures: [Self.lambdaArchitecture(from: architecture)],
            packageType: .zip
        )

        do {
            let response = try await lambdaClient.createFunction(request)
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
                message: error.message ?? error.errorCode
            )
        }
    }

    /// Updates an existing Lambda function's code.
    ///
    /// The function code is provided either as a base64-encoded ZIP payload (direct upload)
    /// or as an S3 bucket/key reference (for archives exceeding the direct upload limit).
    ///
    /// - Parameters:
    ///   - name: The Lambda function name.
    ///   - zipData: The ZIP archive data for direct upload (mutually exclusive with bucket/key).
    ///   - bucket: The S3 bucket containing the deployment package (mutually exclusive with zipData).
    ///   - key: The S3 key of the deployment package (mutually exclusive with zipData).
    ///   - lambdaClient: The Lambda client to use for the API call.
    ///   - verbose: Whether to emit verbose progress output.
    /// - Returns: The response from the UpdateFunctionCode API.
    @discardableResult
    func updateFunctionCode(
        name: String,
        zipData: Data? = nil,
        bucket: String? = nil,
        key: String? = nil,
        using lambdaClient: LambdaClient,
        verbose: Bool
    ) async throws -> UpdateFunctionCodeResponse {
        if verbose {
            if zipData != nil {
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

        let request: UpdateFunctionCodeRequest
        if let zipData {
            request = UpdateFunctionCodeRequest(
                functionName: name,
                zipFile: zipData.base64EncodedString()
            )
        } else {
            request = UpdateFunctionCodeRequest(
                functionName: name,
                s3Bucket: bucket,
                s3Key: key
            )
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
                message: error.message ?? error.errorCode
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
        using lambdaClient: LambdaClient,
        iamClient: IAMClient,
        verbose: Bool
    ) async throws {
        if verbose {
            print("[verbose] Deleting Lambda function '\(name)'...")
        }

        // Delete the function URL config first (ignore errors if not configured)
        do {
            try await lambdaClient.deleteFunctionUrlConfig(
                DeleteFunctionUrlConfigRequest(functionName: name)
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
        let request = DeleteFunctionRequest(functionName: name)
        do {
            try await lambdaClient.deleteFunction(request)
            if verbose {
                print("[verbose] Lambda function '\(name)' deleted successfully")
            }
        } catch let error as LambdaErrorType {
            throw DeployerErrors.awsAPIError(
                service: "Lambda",
                operation: "DeleteFunction",
                message: error.message ?? error.errorCode
            )
        }

        print("Deleted Lambda function '\(name)'")

        // Delete the associated IAM role and its policies
        try await deleteIAMRole(functionName: name, using: iamClient, verbose: verbose)
    }

    // MARK: - Function URL

    /// Configures a Function URL for the Lambda function with IAM authentication
    /// and adds a resource-based permission allowing Function URL invocation.
    ///
    /// - Parameters:
    ///   - functionName: The Lambda function name.
    ///   - lambdaClient: The Lambda client to use for API calls.
    ///   - verbose: Whether to emit verbose progress output.
    /// - Returns: The Function URL string (HTTPS endpoint).
    @discardableResult
    func setupFunctionURL(
        functionName: String,
        accountId: String,
        using lambdaClient: LambdaClient,
        verbose: Bool
    ) async throws -> String {
        if verbose {
            print("[verbose] Creating Function URL for '\(functionName)' with AWS_IAM auth type...")
        }

        // Create the Function URL configuration with IAM authentication
        let createUrlRequest = CreateFunctionUrlConfigRequest(
            functionName: functionName,
            authType: .awsIam
        )

        let createUrlResponse: CreateFunctionUrlConfigResponse
        do {
            createUrlResponse = try await lambdaClient.createFunctionUrlConfig(createUrlRequest)
        } catch let error as LambdaErrorType {
            throw DeployerErrors.functionURLCreationFailed(
                "CreateFunctionUrlConfig failed: \(error.message ?? error.errorCode)"
            )
        }

        guard let functionUrl = createUrlResponse.functionUrl else {
            throw DeployerErrors.functionURLCreationFailed(
                "CreateFunctionUrlConfig succeeded but no URL was returned"
            )
        }

        if verbose {
            print("[verbose] Function URL created: \(functionUrl)")
        }

        // Add resource-based permission for Function URL invocation
        // Scoped to the account to avoid overly-permissive resource policy
        let addPermissionRequest = AddPermissionRequest(
            functionName: functionName,
            statementId: "FunctionURLAllowAccountAccess",
            action: "lambda:InvokeFunctionUrl",
            principal: accountId,
            functionUrlAuthType: .awsIam
        )

        do {
            try await lambdaClient.addPermission(addPermissionRequest)
            if verbose {
                print("[verbose] Added resource-based permission for Function URL invocation")
            }
        } catch let error as LambdaErrorType {
            throw DeployerErrors.functionURLCreationFailed(
                "AddPermission failed: \(error.message ?? error.errorCode)"
            )
        }

        return functionUrl
    }

    // MARK: - Source Code Detection

    /// Scans the Sources directory for usage of `FunctionURLRequest`, indicating
    /// the project was scaffolded with `lambda-init --with-url` and needs a Function URL.
    /// This allows `lambda-deploy` to auto-detect the need for `--with-url`.
    private func detectFunctionURLUsage() -> Bool {
        let sourcesDir = URL(fileURLWithPath: "Sources")
        guard
            let enumerator = FileManager.default.enumerator(
                at: sourcesDir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        else {
            return false
        }

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "swift" else { continue }
            guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            if contents.contains("FunctionURLRequest") || contents.contains("FunctionURLResponse") {
                return true
            }
        }
        return false
    }

    // MARK: - Deploy

    func deploy(arguments: [String]) async throws {
        let configuration = try DeployerConfiguration(arguments: arguments)

        if configuration.help {
            self.displayHelpMessage()
            return
        }

        if configuration.verboseLogging {
            print("-------------------------------------------------------------------------")
            print("configuration")
            print("-------------------------------------------------------------------------")
            print(configuration)
        }

        // Check for AWS configuration files and emit non-blocking warning if absent
        self.checkAWSConfigurationFiles(verbose: configuration.verboseLogging)

        // Initialize AWSClient with the appropriate credential provider.
        // When --profile is specified, build a selector chain that passes the
        // profile name to each provider that understands profiles (configFile,
        // sso, login) — mirroring the structure of .default so profiles using
        // login_session or sso_session resolve, not just static / assume-role.
        // Otherwise, use the default credential provider chain.
        let clientLogger: Logger = {
            var logger = Logger(label: "AWSLambdaDeployer")
            logger.logLevel = configuration.verboseLogging ? .debug : .info
            return logger
        }()

        let credentialProvider: CredentialProviderFactory
        if let profile = configuration.profile {
            if configuration.verboseLogging {
                print("[verbose] Using AWS profile: \(profile)")
            }
            credentialProvider = .selector(
                .configFile(profile: profile),
                .sso(profileName: profile),
                .login(profileName: profile)
            )
        } else {
            credentialProvider = .default
        }

        let awsClient = AWSClient(
            credentialProvider: credentialProvider,
            logger: clientLogger
        )

        do {
            // Resolve the AWS region: use --region override, or fall through to environment/config resolution
            let region: Region
            if let regionOverride = configuration.region {
                region = Region(rawValue: regionOverride)
                if configuration.verboseLogging {
                    print("[verbose] Using region override: \(regionOverride)")
                }
            } else {
                // Resolve region from environment variables (AWS_REGION or AWS_DEFAULT_REGION)
                if let envRegion = ProcessInfo.processInfo.environment["AWS_REGION"]
                    ?? ProcessInfo.processInfo.environment["AWS_DEFAULT_REGION"]
                {
                    region = Region(rawValue: envRegion)
                    if configuration.verboseLogging {
                        print("[verbose] Using region from environment: \(envRegion)")
                    }
                } else {
                    // Default to us-east-1 if no region can be resolved
                    region = .useast1
                    if configuration.verboseLogging {
                        print("[verbose] No region specified or found in environment, defaulting to us-east-1")
                    }
                }
            }

            // Verify credentials can be resolved by attempting to get them
            do {
                _ = try await awsClient.getCredential()
                if configuration.verboseLogging {
                    print("[verbose] AWS credentials resolved successfully")
                }
            } catch {
                throw DeployerErrors.credentialResolutionFailed(
                    "Unable to resolve AWS credentials. "
                        + "If your session has expired, run 'aws sso login' or 'aws login' to refresh it. "
                        + "Otherwise, ensure credentials are configured via "
                        + "environment variables (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY), "
                        + "~/.aws/credentials file, ECS/EKS container credentials, or EC2 instance metadata. "
                        + "Error: \(error)"
                )
            }

            // Initialize service clients
            let stsClient = STSClient(client: awsClient, region: region)
            let lambdaClient = LambdaClient(client: awsClient, region: region)
            let iamClient = IAMClient(client: awsClient, region: region)
            let s3Client = S3Client(client: awsClient, region: region)

            // Resolve account ID via STS
            print("Resolving AWS account ID...")
            let accountId = try await resolveAccountId(using: stsClient)
            if configuration.verboseLogging {
                print("[verbose] AWS account ID: \(accountId)")
            }

            // Determine function name from products
            guard let functionName = configuration.products.first else {
                throw DeployerErrors.missingProduct
            }
            if configuration.delete {
                print("Deleting function '\(functionName)' from \(region.rawValue)...")
            } else {
                print("Deploying function '\(functionName)' to \(region.rawValue)...")
            }

            // Check if function already exists. The configuration is reused downstream (e.g. the
            // update path validates the execution role from it) to avoid a second GetFunction call.
            print("Checking if function '\(functionName)' exists...")
            let existingConfiguration = try await existingFunctionConfiguration(functionName, using: lambdaClient)
            let action = try determineDeploymentAction(
                functionExists: existingConfiguration != nil,
                delete: configuration.delete
            )

            if configuration.verboseLogging {
                print("[verbose] Function '\(functionName)' exists: \(existingConfiguration != nil), action: \(action)")
            }

            switch action {
            case .delete:
                print("Deleting function '\(functionName)'...")
                try await deleteFunction(
                    name: functionName,
                    using: lambdaClient,
                    iamClient: iamClient,
                    verbose: configuration.verboseLogging
                )
                print("🗑️  Function '\(functionName)' deleted successfully.")

            case .create, .update:
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
                    print("[verbose] Archive: \(archiveURL.path) (\(String(format: "%.1f", sizeMB)) MB)")
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
                    let response: CreateFunctionResponse
                    if let bucket = s3Bucket, let key = s3Key {
                        response = try await createFunction(
                            name: functionName,
                            architecture: configuration.architecture,
                            role: roleArn,
                            bucket: bucket,
                            key: key,
                            using: lambdaClient,
                            verbose: configuration.verboseLogging
                        )
                    } else {
                        response = try await createFunction(
                            name: functionName,
                            architecture: configuration.architecture,
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
                    let response: UpdateFunctionCodeResponse
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

                // Set up Function URL if requested (or auto-detected from source code)
                var functionURL: String? = nil
                let shouldSetupURL = configuration.withURL || detectFunctionURLUsage()
                if shouldSetupURL {
                    if action == .create {
                        print("Configuring Function URL...")
                        functionURL = try await setupFunctionURL(
                            functionName: functionName,
                            accountId: accountId,
                            using: lambdaClient,
                            verbose: configuration.verboseLogging
                        )
                    } else {
                        // On update, retrieve the existing Function URL
                        do {
                            let urlConfig = try await lambdaClient.getFunctionUrlConfig(
                                GetFunctionUrlConfigRequest(functionName: functionName)
                            )
                            functionURL = urlConfig.functionUrl
                        } catch {
                            // No URL configured yet — set it up
                            print("Configuring Function URL...")
                            functionURL = try await setupFunctionURL(
                                functionName: functionName,
                                accountId: accountId,
                                using: lambdaClient,
                                verbose: configuration.verboseLogging
                            )
                        }
                    }
                }

                // Report success
                reportDeploymentSuccess(
                    functionName: functionName,
                    functionArn: functionArn
                        ?? "arn:aws:lambda:\(region.rawValue):\(accountId):function:\(functionName)",
                    region: region.rawValue,
                    functionURL: functionURL
                )
            }

            try await awsClient.shutdown()
        } catch {
            try await awsClient.shutdown()
            throw error
        }
    }

    /// Check for the presence of AWS configuration files and emit an informational
    /// warning if they are absent. This is non-blocking — deployment continues
    /// regardless, because credentials may be available from other sources in the
    /// credential provider chain (environment variables, ECS/EKS, EC2 IMDS).
    private func checkAWSConfigurationFiles(verbose: Bool) {
        let homeDirectory: String
        #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
        homeDirectory = NSHomeDirectory()
        #else
        homeDirectory = ProcessInfo.processInfo.environment["HOME"] ?? "~"
        #endif

        let configPath = "\(homeDirectory)/.aws/config"
        let credentialsPath = "\(homeDirectory)/.aws/credentials"

        let configExists = FileManager.default.fileExists(atPath: configPath)
        let credentialsExists = FileManager.default.fileExists(atPath: credentialsPath)

        if !configExists && !credentialsExists {
            print(
                """
                ⚠️  AWS configuration files not found (~/.aws/config and ~/.aws/credentials).
                   If you are running on a developer machine, install the AWS CLI and run
                   'aws configure' to set up your credentials and default region.
                   On EC2, ECS, or EKS, credentials are typically provided automatically
                   by the instance or task role.
                """
            )
        } else if verbose {
            print("[verbose] AWS configuration files found:")
            if configExists { print("  - \(configPath)") }
            if credentialsExists { print("  - \(credentialsPath)") }
        }
    }

    // MARK: - IAM Role Management

    /// The ARN of the AWS managed policy for basic Lambda execution (CloudWatch Logs access).
    private static let lambdaBasicExecutionRolePolicyARN =
        "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"

    /// Constructs the IAM role name for a Lambda function.
    /// Format: `swift-lambda-<functionName>-role`
    static func iamRoleName(for functionName: String) -> String {
        "swift-lambda-\(functionName)-role"
    }

    /// Extracts the role name from an IAM role ARN.
    /// e.g. `arn:aws:iam::123456789012:role/my-role` -> `my-role`,
    /// `arn:aws:iam::123456789012:role/path/my-role` -> `my-role`.
    /// Returns `nil` if the ARN does not contain a role name.
    static func roleName(fromARN arn: String) -> String? {
        guard let slashIndex = arn.lastIndex(of: "/") else { return nil }
        let name = arn[arn.index(after: slashIndex)...]
        return name.isEmpty ? nil : String(name)
    }

    /// Verifies that the IAM role referenced by a function's execution role ARN still exists.
    ///
    /// Lambda only validates that an execution role is assumable lazily, at invoke time, not when
    /// the function is created or updated. If the role was deleted (for example by a previous
    /// `--delete` run), an update would silently succeed but the function would fail to invoke with
    /// `The role defined for the function cannot be assumed by Lambda`. This check surfaces the
    /// problem at deploy time instead.
    ///
    /// - Parameters:
    ///   - roleARN: The execution role ARN configured on the function, if any.
    ///   - functionName: The function name, used for error reporting.
    ///   - iamClient: The IAM client to use for the lookup.
    ///   - verbose: Whether to emit verbose progress output.
    /// - Throws: `DeployerErrors.executionRoleMissing` if the role does not exist.
    func verifyExecutionRoleExists(
        roleARN: String?,
        functionName: String,
        using iamClient: IAMClient,
        verbose: Bool
    ) async throws {
        guard let roleARN, let roleName = Self.roleName(fromARN: roleARN) else {
            // No role ARN to verify (or an unparsable ARN) — nothing to check.
            return
        }

        if verbose {
            print("[verbose] Verifying execution role '\(roleName)' still exists...")
        }

        do {
            _ = try await iamClient.getRole(IAMGetRoleRequest(roleName: roleName))
            if verbose {
                print("[verbose] Execution role '\(roleName)' exists")
            }
        } catch {
            if "\(error)".contains("NoSuchEntity") {
                throw DeployerErrors.executionRoleMissing(functionName: functionName, role: roleARN)
            }
            throw DeployerErrors.awsAPIError(
                service: "IAM",
                operation: "GetRole",
                message: "failed to verify execution role '\(roleName)': \(error)"
            )
        }
    }

    /// The trust policy document that allows Lambda to assume the role.
    private static let lambdaTrustPolicy = """
        {"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}
        """

    /// Creates a new IAM role for the Lambda function with the Lambda trust policy,
    /// attaches the AWSLambdaBasicExecutionRole managed policy, and waits for
    /// role propagation before returning.
    ///
    /// - Parameters:
    ///   - functionName: The Lambda function name used to derive the role name.
    ///   - iamClient: The IAM client to use for API calls.
    ///   - verbose: Whether to emit verbose progress output.
    /// - Returns: The ARN of the created role.
    @discardableResult
    func createIAMRole(functionName: String, using iamClient: IAMClient, verbose: Bool) async throws -> String {
        let roleName = Self.iamRoleName(for: functionName)

        if verbose {
            print("[verbose] Creating IAM role '\(roleName)' with Lambda trust policy...")
        }

        // Create the role with the Lambda assume-role trust policy
        let createRoleRequest = IAMCreateRoleRequest(
            roleName: roleName,
            assumeRolePolicyDocument: Self.lambdaTrustPolicy,
            path: "/",
            description:
                "Execution role for Lambda function '\(functionName)' created by swift-aws-lambda-runtime deploy plugin"
        )

        let createRoleResponse: IAMCreateRoleResponse
        do {
            createRoleResponse = try await iamClient.createRole(createRoleRequest)
        } catch {
            throw DeployerErrors.iamRoleCreationFailed(
                "CreateRole failed for '\(roleName)': \(error)"
            )
        }

        guard let roleARN = createRoleResponse.role?.arn else {
            throw DeployerErrors.iamRoleCreationFailed(
                "CreateRole succeeded but no ARN was returned for '\(roleName)'"
            )
        }

        if verbose {
            print("[verbose] IAM role created: \(roleARN)")
        }

        // Attach the AWSLambdaBasicExecutionRole managed policy
        let attachPolicyRequest = IAMAttachRolePolicyRequest(
            roleName: roleName,
            policyArn: Self.lambdaBasicExecutionRolePolicyARN
        )

        do {
            try await iamClient.attachRolePolicy(attachPolicyRequest)
        } catch {
            throw DeployerErrors.iamRoleCreationFailed(
                "AttachRolePolicy failed for '\(roleName)': \(error)"
            )
        }

        if verbose {
            print("[verbose] Attached AWSLambdaBasicExecutionRole policy to '\(roleName)'")
        }

        // Wait for role propagation — IAM is eventually consistent and the role
        // may not be usable by Lambda immediately after creation.
        if verbose {
            print("[verbose] Waiting 10 seconds for IAM role propagation...")
        }
        try await Task.sleep(for: .seconds(10))

        if verbose {
            print("[verbose] IAM role '\(roleName)' is ready")
        }

        return roleARN
    }

    /// Deletes the IAM role associated with a Lambda function, including
    /// detaching managed policies and deleting inline policies.
    ///
    /// - Parameters:
    ///   - functionName: The Lambda function name used to derive the role name.
    ///   - iamClient: The IAM client to use for API calls.
    ///   - verbose: Whether to emit verbose progress output.
    func deleteIAMRole(functionName: String, using iamClient: IAMClient, verbose: Bool) async throws {
        let roleName = Self.iamRoleName(for: functionName)

        if verbose {
            print("[verbose] Deleting IAM role '\(roleName)'...")
        }

        // Detach the AWSLambdaBasicExecutionRole managed policy
        let detachPolicyRequest = IAMDetachRolePolicyRequest(
            roleName: roleName,
            policyArn: Self.lambdaBasicExecutionRolePolicyARN
        )

        do {
            try await iamClient.detachRolePolicy(detachPolicyRequest)
            if verbose {
                print("[verbose] Detached AWSLambdaBasicExecutionRole from '\(roleName)'")
            }
        } catch {
            // If the policy is not attached, ignore the error and continue
            if verbose {
                print("[verbose] Note: detaching managed policy failed (may not be attached): \(error)")
            }
        }

        // Delete any inline policies that may have been added
        // We use a known inline policy name pattern for cleanup
        let inlinePolicyName = "\(roleName)-inline-policy"
        do {
            let deleteInlinePolicyRequest = IAMDeleteRolePolicyRequest(
                roleName: roleName,
                policyName: inlinePolicyName
            )
            try await iamClient.deleteRolePolicy(deleteInlinePolicyRequest)
            if verbose {
                print("[verbose] Deleted inline policy '\(inlinePolicyName)' from '\(roleName)'")
            }
        } catch {
            // Inline policy may not exist, which is fine
            if verbose {
                print("[verbose] Note: deleting inline policy failed (may not exist): \(error)")
            }
        }

        // Delete the role itself
        let deleteRoleRequest = IAMDeleteRoleRequest(roleName: roleName)
        do {
            try await iamClient.deleteRole(deleteRoleRequest)
            if verbose {
                print("[verbose] IAM role '\(roleName)' deleted successfully")
            }
        } catch {
            throw DeployerErrors.awsAPIError(
                service: "IAM",
                operation: "DeleteRole",
                message: "Failed to delete role '\(roleName)': \(error)"
            )
        }

        print("Deleted IAM role '\(roleName)'")
    }

    /// Resolves the IAM role for a Lambda function deployment.
    ///
    /// If an IAM role ARN is provided via `--iam-role`, it is returned directly.
    /// Otherwise, a new role is created with the Lambda trust policy and the
    /// AWSLambdaBasicExecutionRole managed policy attached.
    ///
    /// - Parameters:
    ///   - functionName: The Lambda function name.
    ///   - iamRole: An optional user-specified IAM role ARN.
    ///   - iamClient: The IAM client to use for API calls.
    ///   - verbose: Whether to emit verbose progress output.
    /// - Returns: The IAM role ARN to use for the Lambda function.
    func resolveIAMRole(
        functionName: String,
        iamRole: String?,
        using iamClient: IAMClient,
        verbose: Bool
    ) async throws -> String {
        // If the user specified an IAM role, use it directly
        if let iamRole {
            if verbose {
                print("[verbose] Using user-specified IAM role: \(iamRole)")
            }
            return iamRole
        }

        // Check if the role already exists
        let roleName = Self.iamRoleName(for: functionName)
        do {
            let getRoleResponse = try await iamClient.getRole(
                IAMGetRoleRequest(roleName: roleName)
            )
            if let existingARN = getRoleResponse.role?.arn {
                if verbose {
                    print("[verbose] Found existing IAM role: \(existingARN)")
                }
                return existingARN
            }
        } catch {
            // Role does not exist — we will create it
            if verbose {
                print("[verbose] IAM role '\(roleName)' not found, creating a new one...")
            }
        }

        // Create a new role
        return try await createIAMRole(functionName: functionName, using: iamClient, verbose: verbose)
    }

    // MARK: - Success Reporting

    /// Reports a successful deployment to the developer, including the function ARN,
    /// deployment region, and a ready-to-use invocation command.
    ///
    /// - Parameters:
    ///   - functionName: The deployed Lambda function name.
    ///   - functionArn: The ARN of the deployed Lambda function.
    ///   - region: The AWS region where the function was deployed.
    ///   - functionURL: The Function URL if `--with-url` was used, or `nil` otherwise.
    func reportDeploymentSuccess(
        functionName: String,
        functionArn: String,
        region: String,
        functionURL: String?
    ) {
        print("")
        print("🚀 Deployment complete!")
        print("   Function ARN: \(functionArn)")
        print("   Region:       \(region)")

        if let functionURL {
            print("   Function URL: \(functionURL)")
            print("")
            print("Invoke your function with:")
            print("")
            print(
                "   (eval $(aws configure export-credentials --format env) && curl --aws-sigv4 \"aws:amz:\(region):lambda\" --user \"$AWS_ACCESS_KEY_ID:$AWS_SECRET_ACCESS_KEY\" -H \"x-amz-security-token: $AWS_SESSION_TOKEN\" \"\(functionURL)?name=World\" )"
            )
        } else {
            print("")
            print("Invoke your function with:")
            print(
                #"   aws lambda invoke --function-name \#(functionName) --region \#(region) --payload $(echo '{"name":"World","age":30}' | base64) /tmp/out.json > /dev/null && cat /tmp/out.json"#
            )
        }
        print("")
    }

    private func displayHelpMessage() {
        print(
            """
            OVERVIEW: A SwiftPM plugin to deploy a Lambda function to AWS.

            USAGE: swift package --allow-network-connections all:443 lambda-deploy
                                 [--help] [--verbose]
                                 [--with-url]
                                 [--delete]
                                 [--region <region>]
                                 [--profile <profile-name>]
                                 [--iam-role <role-arn>]
                                 [--input-directory <path>]
                                 [--architecture <x64 | arm64>]
                                 [--products <list of products>]

            OPTIONS:
            --verbose                     Produce verbose output for debugging.
            --with-url                    Create a Function URL for the Lambda function.
                                          The URL uses AWS_IAM authentication, restricted to
                                          authenticated principals in your AWS account.
            --delete                      Delete the Lambda function, its IAM role, and
                                          Function URL (if any).
            --region <region>             The AWS region to deploy to.
                                          (default: resolved from AWS configuration)
            --profile <profile-name>     The named AWS profile to use for credentials and region.
                                          (default: default credential provider chain)
            --iam-role <role-arn>         The ARN of an existing IAM role for the Lambda function.
                                          (default: create a new role)
            --input-directory <path>      The path to the directory containing the deployment
                                          ZIP archive produced by lambda-build.
                                          (default: .build/plugins/AWSLambdaBuilder/outputs/...)
            --architecture <arch>         The Lambda function architecture (x64 or arm64).
                                          (default: host architecture - \(DeployerConfiguration.Architecture.host.rawValue))
            --products <list>             The list of executable targets to deploy.
                                          (default is taken from Package.swift)
            --help                        Show help information.
            """
        )
    }
}

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
        }
        """
    }
}

@available(LambdaSwift 2.0, *)
enum DeployerErrors: Error, CustomStringConvertible {
    case invalidArchitecture(String)
    case credentialResolutionFailed(String)
    case awsAPIError(service: String, operation: String, message: String)
    case archiveNotFound(URL)
    case functionURLCreationFailed(String)
    case iamRoleCreationFailed(String)
    case executionRoleMissing(functionName: String, role: String)
    case missingProduct

    var description: String {
        switch self {
        case .invalidArchitecture(let value):
            return "invalid architecture '\(value)'. Use 'x64' or 'arm64'."
        case .credentialResolutionFailed(let message):
            return "AWS credential resolution failed: \(message)"
        case .awsAPIError(let service, let operation, let message):
            return "AWS \(service) \(operation) error: \(message)"
        case .archiveNotFound(let url):
            return "deployment archive not found at '\(url.path())'"
        case .functionURLCreationFailed(let message):
            return "failed to create Function URL: \(message)"
        case .iamRoleCreationFailed(let message):
            return "failed to create IAM role: \(message)"
        case .executionRoleMissing(let functionName, let role):
            return """
                the execution role configured for function '\(functionName)' no longer exists in IAM:
                    \(role)
                Lambda cannot assume a role that does not exist, so the function would fail to invoke.

                Suggested action: delete the function and redeploy it so the role is recreated:
                    swift package --allow-network-connections all:443 lambda-deploy --delete
                    swift package --allow-network-connections all:443 lambda-deploy
                """
        case .missingProduct:
            return "no product specified. Use --products or define an executable target in Package.swift."
        }
    }
}
