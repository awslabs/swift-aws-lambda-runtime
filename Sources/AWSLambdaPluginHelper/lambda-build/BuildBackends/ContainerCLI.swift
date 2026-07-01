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

/// The command-line argument "flavor" of a container runtime CLI (docker, Apple's `container`,
/// and future runtimes such as podman, finch, or colima).
///
/// This abstracts only *how arguments are spelled* for a given CLI — the build flow that uses
/// them lives in ``ContainerBuildBackend``. Each conforming type builds its complete argument
/// vector independently: there is intentionally **no** shared helper or default implementation of
/// these methods. Two runtimes that happen to share an argument layout today may diverge in a
/// future release, and future runtimes may not be compatible at all, so each owns its own argv in
/// full and is covered by its own tests.
@available(LambdaSwift 2.0, *)
protocol ContainerCLI {
    /// The name of the executable to resolve and run (e.g. "docker", "container").
    var executableName: String { get }

    /// The arguments to pull (update) the given base image for a target architecture.
    func pullArguments(image: String, architecture: BuildArchitecture) -> [String]

    /// The arguments to run a command inside a container created from `baseImage`.
    ///
    /// - Parameters:
    ///   - baseImage: The container image to run.
    ///   - architecture: The CPU architecture the container should run as. The build compiles for
    ///     the container's architecture, so this is what determines the produced binary's
    ///     architecture and must match what the function is deployed for.
    ///   - workingDirectory: The working directory inside the container.
    ///   - mounts: Volume mounts, each in the CLI's `host:container` form.
    ///   - env: Environment variables to set inside the container, or `nil`.
    ///   - command: The shell command to execute inside the container.
    func runArguments(
        baseImage: String,
        architecture: BuildArchitecture,
        workingDirectory: String,
        mounts: [String],
        env: [String: String]?,
        command: String
    ) -> [String]

    /// The arguments to build an OCI image from a Dockerfile for a single target architecture.
    ///
    /// - Parameters:
    ///   - dockerfile: Path to the Dockerfile to build.
    ///   - contextDir: The build context directory (the directory containing the files the
    ///     Dockerfile's `COPY`/`ADD` instructions reference).
    ///   - tag: The image tag to apply (e.g. `swift-lambda/MyLambda:latest`).
    ///   - architecture: The single CPU architecture to build for. AWS Lambda images are
    ///     single-architecture, so this is always baked in explicitly rather than left to the
    ///     daemon default.
    func buildImageArguments(
        dockerfile: String,
        contextDir: String,
        tag: String,
        architecture: BuildArchitecture
    ) -> [String]

    /// The arguments to log in to a container registry, reading the password from stdin.
    ///
    /// The caller pipes the secret to the process's standard input (e.g. an ECR authorization
    /// token), so the password never appears in the argument vector. For ECR the username is
    /// always `AWS`.
    ///
    /// - Parameters:
    ///   - registry: The registry host to authenticate against (e.g.
    ///     `<account>.dkr.ecr.<region>.amazonaws.com`).
    ///   - username: The registry username (`AWS` for ECR).
    func loginArguments(registry: String, username: String) -> [String]

    /// The arguments to re-tag a local image under a new reference (e.g. the ECR-qualified name).
    func tagArguments(source: String, target: String) -> [String]

    /// The arguments to push a tagged image to its registry.
    func pushArguments(tag: String) -> [String]
}
