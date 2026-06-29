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

    func pullArguments(image: String) -> [String] {
        ["pull", image]
    }

    func runArguments(
        baseImage: String,
        workingDirectory: String,
        mounts: [String],
        env: [String: String]?,
        command: String
    ) -> [String] {
        var args: [String] = ["run", "--rm"]
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
}
