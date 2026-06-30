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
    func resolveAccountId(using stsClient: STS) async throws -> String {
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
        using lambdaClient: Lambda
    ) async throws -> Lambda.FunctionConfiguration? {
        do {
            return try await lambdaClient.getFunction(
                Lambda.GetFunctionRequest(functionName: functionName)
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
            let stsClient = STS(client: awsClient, region: region)
            let lambdaClient = Lambda(client: awsClient, region: region)
            let iamClient = IAM(client: awsClient)
            let s3Client = S3(client: awsClient, region: region)

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
                let functionArn: String?

                // Read the build manifest (written by lambda-build next to the artifact) to learn
                // the package type. Absent manifest → ZIP, for backwards compatibility.
                let manifest = try Self.readBuildManifest(
                    functionName: functionName,
                    inputDirectory: configuration.inputDirectory
                )

                // Guard package-type immutability: AWS forbids changing a function's package type.
                if let existingType = existingConfiguration?.packageType {
                    let requestedType: Lambda.PackageType = (manifest?.packageType == .image) ? .image : .zip
                    if existingType != requestedType {
                        throw DeployerErrors.packageTypeMismatch(
                            functionName: functionName,
                            existing: existingType.rawValue,
                            requested: requestedType.rawValue
                        )
                    }
                }

                if manifest?.packageType == .image {
                    functionArn = try await deployImage(
                        functionName: functionName,
                        manifest: manifest!,
                        action: action,
                        accountId: accountId,
                        region: region,
                        configuration: configuration,
                        existingConfiguration: existingConfiguration,
                        awsClient: awsClient,
                        lambdaClient: lambdaClient,
                        iamClient: iamClient
                    )
                } else {
                    functionArn = try await deployZip(
                        functionName: functionName,
                        action: action,
                        accountId: accountId,
                        region: region,
                        configuration: configuration,
                        existingConfiguration: existingConfiguration,
                        lambdaClient: lambdaClient,
                        iamClient: iamClient,
                        s3Client: s3Client
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
                                Lambda.GetFunctionUrlConfigRequest(functionName: functionName)
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

    /// The default directory holding a product's build output (and `build-manifest.json`), matching
    /// the path `lambda-build` writes to.
    static func defaultBuildOutputDirectory(functionName: String, inputDirectory: URL?) -> URL {
        if let inputDirectory {
            return inputDirectory.appending(path: functionName)
        }
        return URL(fileURLWithPath: ".build/plugins/AWSLambdaBuilder/outputs/AWSLambdaBuilder/\(functionName)")
    }

    /// Reads the build manifest written by `lambda-build` beside the artifact, or `nil` if absent
    /// (in which case the deploy falls back to the legacy ZIP path convention).
    static func readBuildManifest(functionName: String, inputDirectory: URL?) throws -> BuildManifest? {
        let dir = defaultBuildOutputDirectory(functionName: functionName, inputDirectory: inputDirectory)
        return try BuildManifest.read(from: dir)
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
                                 [--cross-compile <docker | container>]
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
            --cross-compile <cli>         The container CLI (docker or container) used to push an
                                          OCI image to ECR. Only used for an image artifact
                                          (lambda-build --archive-format oci).
                                          (default: the CLI recorded in the build manifest, else docker)
            --products <list>             The list of executable targets to deploy.
                                          (default is taken from Package.swift)
            --help                        Show help information.
            """
        )
    }
}
