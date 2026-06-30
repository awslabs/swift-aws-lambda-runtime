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
        using lambdaClient: Lambda,
        verbose: Bool
    ) async throws -> String {
        if verbose {
            print("[verbose] Creating Function URL for '\(functionName)' with AWS_IAM auth type...")
        }

        // Create the Function URL configuration with IAM authentication
        let createUrlRequest = Lambda.CreateFunctionUrlConfigRequest(
            authType: .awsIam,
            functionName: functionName
        )

        let createUrlResponse: Lambda.CreateFunctionUrlConfigResponse
        do {
            createUrlResponse = try await lambdaClient.createFunctionUrlConfig(createUrlRequest)
        } catch let error as LambdaErrorType {
            throw DeployerErrors.functionURLCreationFailed(
                "CreateFunctionUrlConfig failed: \(error.context?.message ?? error.errorCode)"
            )
        }

        let functionUrl = createUrlResponse.functionUrl

        if verbose {
            print("[verbose] Function URL created: \(functionUrl)")
        }

        // Add resource-based permission for Function URL invocation
        // Scoped to the account to avoid overly-permissive resource policy
        let addPermissionRequest = Lambda.AddPermissionRequest(
            action: "lambda:InvokeFunctionUrl",
            functionName: functionName,
            functionUrlAuthType: .awsIam,
            principal: accountId,
            statementId: "FunctionURLAllowAccountAccess"
        )

        do {
            _ = try await lambdaClient.addPermission(addPermissionRequest)
            if verbose {
                print("[verbose] Added resource-based permission for Function URL invocation")
            }
        } catch let error as LambdaErrorType {
            throw DeployerErrors.functionURLCreationFailed(
                "AddPermission failed: \(error.context?.message ?? error.errorCode)"
            )
        }

        return functionUrl
    }

    // MARK: - Source Code Detection

    /// Scans the Sources directory for usage of `FunctionURLRequest`, indicating
    /// the project was scaffolded with `lambda-init --with-url` and needs a Function URL.
    /// This allows `lambda-deploy` to auto-detect the need for `--with-url`.
    func detectFunctionURLUsage() -> Bool {
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
}
