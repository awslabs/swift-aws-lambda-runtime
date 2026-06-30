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

/// The Apple `container` CLI argument flavor (https://github.com/apple/container).
///
/// This type builds its complete argument vector on its own and shares no helper with other
/// ``ContainerCLI`` implementations — see the note on ``ContainerCLI``. Its argument layout
/// deliberately differs from Docker's where the CLIs differ: the image subcommand is
/// `image pull` rather than `pull`, and the runtime needs an explicit `--memory` reservation.
@available(LambdaSwift 2.0, *)
struct AppleContainerCLI: ContainerCLI {
    let executableName = "container"

    func pullArguments(image: String) -> [String] {
        ["image", "pull", image]
    }

    func runArguments(
        baseImage: String,
        workingDirectory: String,
        mounts: [String],
        env: [String: String]?,
        command: String
    ) -> [String] {
        // container's runtime needs a bit more memory than the default
        var args: [String] = ["run", "--memory", "4G", "--rm"]
        for mount in mounts {
            args += ["-v", mount]
        }
        if let env {
            for (key, value) in env.sorted(by: { $0.key < $1.key }) {
                args += ["-e", "\(key)=\(value)"]
            }
        }
        args += ["-w", workingDirectory, baseImage, "bash", "-cl", command]
        return args
    }

    func buildImageArguments(
        dockerfile: String,
        contextDir: String,
        tag: String,
        architecture: BuildArchitecture
    ) -> [String] {
        // `container build` defaults its context to `.` and that misbehaves (the COPY context comes
        // through empty), so the context directory is always passed explicitly alongside an
        // explicit `-f`. `--arch` selects the single target architecture.
        [
            "build",
            "--arch", architecture.containerArch,
            "-f", dockerfile,
            "-t", tag,
            contextDir,
        ]
    }

    func loginArguments(registry: String, username: String) -> [String] {
        // container authenticates registries under the `registry login` subcommand, unlike docker's
        // top-level `login`. Verified working against ECR with `--password-stdin`.
        ["registry", "login", "--username", username, "--password-stdin", registry]
    }

    func tagArguments(source: String, target: String) -> [String] {
        ["image", "tag", source, target]
    }

    func pushArguments(tag: String) -> [String] {
        ["image", "push", tag]
    }
}
