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

/// The target CPU architecture an artifact is built for.
///
/// An OCI image bakes in a single architecture, so the build step needs to know which one to
/// target. Today this defaults to the host architecture; a user-facing `--architecture` flag and
/// build-manifest plumbing are tracked separately (issue #683) and will set this explicitly.
@available(LambdaSwift 2.0, *)
enum BuildArchitecture: String, Codable, CustomStringConvertible {
    case x64
    case arm64

    /// The architecture of the machine running the build.
    static var host: BuildArchitecture {
        #if arch(x86_64)
        return .x64
        #else
        return .arm64
        #endif
    }

    /// The value docker's `--platform` flag expects (`linux/amd64`, `linux/arm64`).
    var dockerPlatform: String {
        switch self {
        case .x64: return "linux/amd64"
        case .arm64: return "linux/arm64"
        }
    }

    /// The value Apple `container`'s `--arch` flag expects (`amd64`, `arm64`).
    var containerArch: String {
        switch self {
        case .x64: return "amd64"
        case .arm64: return "arm64"
        }
    }

    var description: String {
        self.rawValue
    }
}
