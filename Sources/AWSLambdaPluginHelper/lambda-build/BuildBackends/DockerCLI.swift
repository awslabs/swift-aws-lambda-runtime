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

/// The Docker CLI argument flavor.
///
/// This type builds its complete argument vector on its own and shares no helper with other
/// ``ContainerCLI`` implementations — see the note on ``ContainerCLI``.
@available(LambdaSwift 2.0, *)
struct DockerCLI: ContainerCLI {
    let executableName = "docker"

    /// The value docker's `--platform` flag expects (`linux/amd64`, `linux/arm64`).
    func platform(for architecture: BuildArchitecture) -> String {
        switch architecture {
        case .x64: return "linux/amd64"
        case .arm64: return "linux/arm64"
        }
    }

    func pullArguments(image: String, architecture: BuildArchitecture) -> [String] {
        ["pull", "--platform", self.platform(for: architecture), image]
    }

    func runArguments(
        baseImage: String,
        architecture: BuildArchitecture,
        workingDirectory: String,
        mounts: [String],
        env: [String: String]?,
        command: String
    ) -> [String] {
        var args: [String] = ["run", "--platform", self.platform(for: architecture), "--rm"]
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
        [
            "build",
            "--platform", self.platform(for: architecture),
            "-f", dockerfile,
            "-t", tag,
            contextDir,
        ]
    }

    func loginArguments(registry: String, username: String) -> [String] {
        ["login", "--username", username, "--password-stdin", registry]
    }

    func tagArguments(source: String, target: String) -> [String] {
        ["tag", source, target]
    }

    func pushArguments(tag: String) -> [String] {
        ["push", tag]
    }
}
