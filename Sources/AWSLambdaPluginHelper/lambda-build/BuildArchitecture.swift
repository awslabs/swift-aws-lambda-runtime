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
/// Set explicitly by `--architecture` (defaulting to the host architecture) and recorded in the
/// build manifest so `lambda-deploy` deploys the function for the architecture the binary was
/// actually built for. Both the ZIP and OCI archive backends target this single architecture.
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

    /// Parses the `--architecture` value, defaulting to the host architecture when omitted.
    static func parse(_ value: String?) throws -> Self {
        guard let value else {
            return .host
        }
        guard let architecture = BuildArchitecture(rawValue: value.lowercased()) else {
            throw BuilderErrors.invalidArgument(
                "invalid architecture '\(value)'. Use 'x64' or 'arm64'."
            )
        }
        return architecture
    }

    var description: String {
        self.rawValue
    }
}
