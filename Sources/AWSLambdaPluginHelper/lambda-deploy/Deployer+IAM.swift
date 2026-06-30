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
    // MARK: - IAM Role Management

    /// The ARN of the AWS managed policy for basic Lambda execution (CloudWatch Logs access).
    static let lambdaBasicExecutionRolePolicyARN =
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
        using iamClient: IAM,
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
            _ = try await iamClient.getRole(IAM.GetRoleRequest(roleName: roleName))
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
    func createIAMRole(functionName: String, using iamClient: IAM, verbose: Bool) async throws -> String {
        let roleName = Self.iamRoleName(for: functionName)

        if verbose {
            print("[verbose] Creating IAM role '\(roleName)' with Lambda trust policy...")
        }

        // Create the role with the Lambda assume-role trust policy
        let createRoleRequest = IAM.CreateRoleRequest(
            assumeRolePolicyDocument: Self.lambdaTrustPolicy,
            description:
                "Execution role for Lambda function '\(functionName)' created by swift-aws-lambda-runtime deploy plugin",
            path: "/",
            roleName: roleName
        )

        let createRoleResponse: IAM.CreateRoleResponse
        do {
            createRoleResponse = try await iamClient.createRole(createRoleRequest)
        } catch {
            throw DeployerErrors.iamRoleCreationFailed(
                "CreateRole failed for '\(roleName)': \(error)"
            )
        }

        let roleARN = createRoleResponse.role.arn

        if verbose {
            print("[verbose] IAM role created: \(roleARN)")
        }

        // Attach the AWSLambdaBasicExecutionRole managed policy
        let attachPolicyRequest = IAM.AttachRolePolicyRequest(
            policyArn: Self.lambdaBasicExecutionRolePolicyARN,
            roleName: roleName
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

        // No fixed propagation wait here. IAM is eventually consistent, so a freshly created role
        // may not be assumable by Lambda for a short window; CreateFunction retries on that specific
        // error (see `createFunction`), which is typically far faster than an unconditional sleep.
        return roleARN
    }

    /// Deletes the IAM role associated with a Lambda function, including
    /// detaching managed policies and deleting inline policies.
    ///
    /// - Parameters:
    ///   - functionName: The Lambda function name used to derive the role name.
    ///   - iamClient: The IAM client to use for API calls.
    ///   - verbose: Whether to emit verbose progress output.
    func deleteIAMRole(functionName: String, using iamClient: IAM, verbose: Bool) async throws {
        let roleName = Self.iamRoleName(for: functionName)

        if verbose {
            print("[verbose] Deleting IAM role '\(roleName)'...")
        }

        // Detach the AWSLambdaBasicExecutionRole managed policy
        let detachPolicyRequest = IAM.DetachRolePolicyRequest(
            policyArn: Self.lambdaBasicExecutionRolePolicyARN,
            roleName: roleName
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
            let deleteInlinePolicyRequest = IAM.DeleteRolePolicyRequest(
                policyName: inlinePolicyName,
                roleName: roleName
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
        let deleteRoleRequest = IAM.DeleteRoleRequest(roleName: roleName)
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
        using iamClient: IAM,
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
                IAM.GetRoleRequest(roleName: roleName)
            )
            let existingARN = getRoleResponse.role.arn
            if verbose {
                print("[verbose] Found existing IAM role: \(existingARN)")
            }
            return existingARN
        } catch {
            // Role does not exist — we will create it
            if verbose {
                print("[verbose] IAM role '\(roleName)' not found, creating a new one...")
            }
        }

        // Create a new role
        return try await createIAMRole(functionName: functionName, using: iamClient, verbose: verbose)
    }
}
