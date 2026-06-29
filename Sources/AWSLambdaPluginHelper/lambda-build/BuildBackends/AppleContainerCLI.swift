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
}
