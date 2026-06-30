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
enum DeployerErrors: Error, CustomStringConvertible {
    case invalidArchitecture(String)
    case credentialResolutionFailed(String)
    case awsAPIError(service: String, operation: String, message: String)
    case archiveNotFound(URL)
    case functionURLCreationFailed(String)
    case iamRoleCreationFailed(String)
    case executionRoleMissing(functionName: String, role: String)
    case missingProduct
    case ecrError(String)
    case imageManifestNotAnIndex
    case packageTypeMismatch(functionName: String, existing: String, requested: String)

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
        case .ecrError(let message):
            return "ECR error: \(message)"
        case .imageManifestNotAnIndex:
            return "the pushed image is a flat manifest, not an index"
        case .packageTypeMismatch(let functionName, let existing, let requested):
            return """
                function '\(functionName)' already exists with package type '\(existing)', but the \
                artifact is '\(requested)'. AWS does not allow changing the package type of an existing \
                function.

                Suggested action: delete the function and redeploy it:
                    swift package --allow-network-connections all:443 lambda-deploy --delete
                    swift package --allow-network-connections all:443 lambda-deploy
                """
        }
    }
}
