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
    // MARK: - Image (OCI) deploy

    /// Deploys an OCI image artifact (built by `lambda-build --archive-format oci`) as an
    /// `Image`-packaged Lambda function, returning the function ARN.
    ///
    /// The flow, all at deploy time (the only step that holds AWS credentials and network access):
    /// ensure the ECR repository exists → obtain an ECR auth token and `login` the container CLI →
    /// re-`tag` the local image under the ECR-qualified name → `push` → resolve the child manifest
    /// digest (Lambda rejects multi-arch image indexes, so we unwrap the index to the single-arch
    /// child) → `create`/`update` the function with `PackageType=Image` and `Code.ImageUri`.
    ///
    /// The container steps (`login`/`tag`/`push`) shell out through the same ``ContainerCLI`` argv
    /// abstraction used by the build; the ECR API calls go through the generated ``ECR`` client.
    func deployImage(
        functionName: String,
        manifest: BuildManifest,
        action: DeploymentAction,
        accountId: String,
        region: Region,
        configuration: DeployerConfiguration,
        existingConfiguration: Lambda.FunctionConfiguration?,
        awsClient: AWSClient,
        lambdaClient: Lambda,
        iamClient: IAM
    ) async throws -> String? {
        let verbose = configuration.verboseLogging

        guard let localTag = manifest.imageTag else {
            throw DeployerErrors.ecrError("build manifest for '\(functionName)' has no image tag")
        }

        // Resolve the container CLI and the matching executable path (see resolveContainerCLI).
        let (cli, toolPath) = try Self.resolveContainerCLI(configuration: configuration, manifest: manifest)

        // Image architecture comes from the manifest (the image bakes in a single arch).
        let architecture = DeployerConfiguration.Architecture(rawValue: manifest.architecture.rawValue) ?? .host

        let ecrClient = ECR(client: awsClient, region: region)

        // 1. Ensure the ECR repository exists.
        let repository = Self.ecrRepositoryName(for: functionName)
        let repositoryUri = try await ensureECRRepositoryExists(
            repository: repository,
            using: ecrClient,
            verbose: verbose
        )

        // 2. Authenticate the container CLI to the registry.
        let registry = Self.ecrRegistryHost(accountId: accountId, region: region.rawValue)
        let (username, password) = try await ecrAuthorization(using: ecrClient, verbose: verbose)

        // 3. Tag + push the local image under the ECR-qualified reference.
        let pushTag = "latest"
        let ecrReference = Self.ecrImageReference(
            accountId: accountId,
            region: region.rawValue,
            repository: repository,
            tag: pushTag
        )
        try ecrLoginTagAndPush(
            cli: cli,
            toolPath: toolPath,
            localTag: localTag,
            registry: registry,
            ecrReference: ecrReference,
            username: username,
            password: password,
            verbose: verbose
        )

        // 4. Unwrap the pushed index to the single-arch child manifest digest (Lambda rejects indexes).
        let deployableReference = try await resolveDeployableImageReference(
            repository: repository,
            repositoryUri: repositoryUri,
            tag: pushTag,
            architecture: architecture,
            using: ecrClient,
            verbose: verbose
        )

        // 5. Create or update the Image function.
        let functionArn: String?
        if action == .create {
            print("Resolving IAM role...")
            let roleArn = try await resolveIAMRole(
                functionName: functionName,
                iamRole: configuration.iamRole,
                using: iamClient,
                verbose: verbose
            )
            print("Creating image Lambda function '\(functionName)'...")
            let response = try await createFunction(
                name: functionName,
                architecture: architecture,
                role: roleArn,
                imageUri: deployableReference,
                using: lambdaClient,
                verbose: verbose
            )
            functionArn = response.functionArn
        } else {
            try await verifyExecutionRoleExists(
                roleARN: existingConfiguration?.role,
                functionName: functionName,
                using: iamClient,
                verbose: verbose
            )
            print("Updating image Lambda function '\(functionName)'...")
            let response = try await updateFunctionCode(
                name: functionName,
                imageUri: deployableReference,
                using: lambdaClient,
                verbose: verbose
            )
            functionArn = response.functionArn
        }
        return functionArn
    }

    // MARK: - Container CLI

    /// Resolves the container CLI to use for the push and its matching executable path.
    ///
    /// The CLI *flavor* (docker vs Apple `container`, which spell their argv differently) is chosen
    /// as: explicit `--cross-compile` wins, else the CLI recorded in the build manifest, else docker.
    /// The plugin wrapper resolves every installed CLI up front — it cannot know which flavor to use
    /// before the manifest is read, and the sandbox only runs tools resolved ahead of time — and
    /// forwards their paths keyed by name. This picks the path for the chosen flavor, so the argv
    /// flavor and the executable can never disagree (the bug where container-style argv was run
    /// against the docker binary, producing `docker registry login … unknown flag: --username`).
    static func resolveContainerCLI(
        configuration: DeployerConfiguration,
        manifest: BuildManifest
    ) throws -> (cli: any ContainerCLI, toolPath: URL) {
        let cliName = configuration.crossCompile ?? manifest.containerCLI ?? "docker"
        guard let toolPath = configuration.crossCompileToolPaths[cliName] else {
            throw DeployerErrors.ecrError(
                "deploying this image requires the '\(cliName)' CLI, but the plugin did not resolve "
                    + "its path (is '\(cliName)' installed and on your PATH?). The image was built with "
                    + "'\(manifest.containerCLI ?? "docker")'; deploy with that CLI, or pass "
                    + "--cross-compile <docker|container> to override."
            )
        }
        let cli: any ContainerCLI = (cliName == "container") ? AppleContainerCLI() : DockerCLI()
        return (cli, toolPath)
    }

    // MARK: - ECR repository

    /// The ECR repository name for a function. Mirrors the function name, lowercased: ECR
    /// repository names (like OCI image references) must be lowercase.
    static func ecrRepositoryName(for functionName: String) -> String {
        functionName.lowercased()
    }

    /// The registry host for an account/region (`<account>.dkr.ecr.<region>.amazonaws.com`).
    static func ecrRegistryHost(accountId: String, region: String) -> String {
        "\(accountId).dkr.ecr.\(region).amazonaws.com"
    }

    /// The ECR-qualified image reference (`<registry>/<repo>:<tag>`).
    static func ecrImageReference(accountId: String, region: String, repository: String, tag: String) -> String {
        "\(Self.ecrRegistryHost(accountId: accountId, region: region))/\(repository):\(tag)"
    }

    /// Ensures the ECR repository exists, creating it if absent. Returns the repository URI.
    @discardableResult
    func ensureECRRepositoryExists(
        repository: String,
        using ecrClient: ECR,
        verbose: Bool
    ) async throws -> String {
        if verbose {
            print("[verbose] Checking if ECR repository '\(repository)' exists...")
        }

        do {
            let response = try await ecrClient.describeRepositories(
                ECR.DescribeRepositoriesRequest(repositoryNames: [repository])
            )
            if let uri = response.repositories?.first?.repositoryUri {
                if verbose { print("[verbose] ECR repository exists: \(uri)") }
                return uri
            }
        } catch {
            // RepositoryNotFoundException → fall through to create. Anything else is surfaced by
            // the create call (or rethrown there).
            if verbose {
                print("[verbose] ECR repository '\(repository)' not found, creating it...")
            }
        }

        do {
            let response = try await ecrClient.createRepository(
                ECR.CreateRepositoryRequest(repositoryName: repository)
            )
            guard let uri = response.repository?.repositoryUri else {
                throw DeployerErrors.ecrError("CreateRepository for '\(repository)' returned no repository URI")
            }
            if verbose { print("[verbose] Created ECR repository: \(uri)") }
            return uri
        } catch let error as ECRErrorType {
            // Tolerate a concurrent create.
            if "\(error)".contains("RepositoryAlreadyExists") {
                let response = try await ecrClient.describeRepositories(
                    ECR.DescribeRepositoriesRequest(repositoryNames: [repository])
                )
                if let uri = response.repositories?.first?.repositoryUri {
                    return uri
                }
            }
            throw DeployerErrors.awsAPIError(
                service: "ECR",
                operation: "CreateRepository",
                message: error.context?.message ?? error.errorCode
            )
        }
    }

    // MARK: - Auth + push

    /// Obtains an ECR authorization token and decodes it into (username, password).
    ///
    /// ECR returns a base64 `user:password` blob; for ECR the username is always `AWS`.
    func ecrAuthorization(using ecrClient: ECR, verbose: Bool) async throws -> (username: String, password: String) {
        if verbose { print("[verbose] Requesting ECR authorization token...") }

        let response = try await ecrClient.getAuthorizationToken(ECR.GetAuthorizationTokenRequest())
        guard let token = response.authorizationData?.first?.authorizationToken,
            let decoded = Data(base64Encoded: token),
            let pair = String(data: decoded, encoding: .utf8)
        else {
            throw DeployerErrors.ecrError("GetAuthorizationToken returned no usable token")
        }
        // The decoded form is "<username>:<password>".
        guard let colon = pair.firstIndex(of: ":") else {
            throw DeployerErrors.ecrError("malformed ECR authorization token")
        }
        let username = String(pair[..<colon])
        let password = String(pair[pair.index(after: colon)...])
        return (username, password)
    }

    /// Logs the container CLI into the registry, re-tags the local image under the ECR-qualified
    /// reference, and pushes it.
    func ecrLoginTagAndPush(
        cli: ContainerCLI,
        toolPath: URL,
        localTag: String,
        registry: String,
        ecrReference: String,
        username: String,
        password: String,
        verbose: Bool
    ) throws {
        let logLevel: Utils.ProcessLogLevel = verbose ? .debug : .output

        print("Logging in to ECR registry \(registry)...")
        try Utils.execute(
            executable: toolPath,
            arguments: cli.loginArguments(registry: registry, username: username),
            standardInput: password,
            logLevel: logLevel
        )

        print("Tagging image \(localTag) → \(ecrReference)...")
        try Utils.execute(
            executable: toolPath,
            arguments: cli.tagArguments(source: localTag, target: ecrReference),
            logLevel: logLevel
        )

        print("Pushing image to ECR...")
        try Utils.execute(
            executable: toolPath,
            arguments: cli.pushArguments(tag: ecrReference),
            logLevel: logLevel
        )
    }

    // MARK: - Index unwrap

    /// Resolves the deployable image reference (`<repo>@<child-digest>`) for a pushed tag.
    ///
    /// Both docker and Apple `container` push an OCI image *index* by default (provenance/SBOM
    /// attestations force a manifest list). Lambda rejects an index — it needs a flat,
    /// single-platform manifest — so we read the index from ECR and select the child whose
    /// `platform.architecture` matches the target, then deploy that child by digest.
    func resolveDeployableImageReference(
        repository: String,
        repositoryUri: String,
        tag: String,
        architecture: DeployerConfiguration.Architecture,
        using ecrClient: ECR,
        verbose: Bool
    ) async throws -> String {
        if verbose { print("[verbose] Resolving child manifest digest for arch \(architecture.rawValue)...") }

        let response = try await ecrClient.batchGetImage(
            ECR.BatchGetImageRequest(
                imageIds: [ECR.ImageIdentifier(imageTag: tag)],
                repositoryName: repository
            )
        )
        guard let manifestString = response.images?.first?.imageManifest else {
            throw DeployerErrors.ecrError("BatchGetImage returned no manifest for \(repository):\(tag)")
        }

        let digest = try Self.childManifestDigest(
            indexManifestJSON: manifestString,
            architecture: architecture
        )
        // repositoryUri is "<registry>/<repo>"; address the child by digest.
        return "\(repositoryUri)@\(digest)"
    }

    /// Parses an OCI image index JSON and returns the digest of the child manifest matching `architecture`.
    ///
    /// If the manifest is already a flat single-platform manifest (no `manifests` array), the caller
    /// should deploy the tag directly; this function throws `imageManifestNotAnIndex` so the caller
    /// can fall back. Uses `JSONDecoder` (FoundationEssentials-safe) rather than `JSONSerialization`,
    /// which is unavailable on Linux.
    static func childManifestDigest(
        indexManifestJSON: String,
        architecture: DeployerConfiguration.Architecture
    ) throws -> String {
        guard let data = indexManifestJSON.data(using: .utf8) else {
            throw DeployerErrors.ecrError("could not read image manifest JSON")
        }
        let index: ImageIndex
        do {
            index = try JSONDecoder().decode(ImageIndex.self, from: data)
        } catch {
            throw DeployerErrors.ecrError("could not parse image manifest JSON: \(error)")
        }

        guard let manifests = index.manifests else {
            throw DeployerErrors.imageManifestNotAnIndex
        }

        let wantArch = Self.ociArchitecture(for: architecture)
        for child in manifests {
            // Skip attestation/unknown entries (platform.architecture == "unknown").
            if child.platform?.architecture == wantArch, let digest = child.digest {
                return digest
            }
        }
        throw DeployerErrors.ecrError("no child manifest for architecture '\(wantArch)' in image index")
    }

    /// The OCI `platform.architecture` string for a deploy architecture.
    static func ociArchitecture(for architecture: DeployerConfiguration.Architecture) -> String {
        switch architecture {
        case .x64: return "amd64"
        case .arm64: return "arm64"
        }
    }

    /// The subset of an OCI image index we need to select a child manifest by architecture.
    private struct ImageIndex: Decodable {
        struct Manifest: Decodable {
            struct Platform: Decodable {
                let architecture: String?
            }
            let digest: String?
            let platform: Platform?
        }
        let manifests: [Manifest]?
    }
}
