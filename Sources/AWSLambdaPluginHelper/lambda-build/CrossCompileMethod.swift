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

/// The cross-compilation method requested via `--cross-compile`.
///
/// This enum is the parsed user choice and a factory for the matching ``BuildBackend``. It holds
/// no execution logic itself: container argument spelling lives in the ``ContainerCLI`` types and
/// the build flow lives in the ``BuildBackend`` types.
@available(LambdaSwift 2.0, *)
enum CrossCompileMethod: String, CustomStringConvertible {
    case docker
    case container
    case swiftStaticSdk = "swift-static-sdk"
    case customSdk = "custom-sdk"

    var isSupported: Bool {
        switch self {
        case .docker, .container: return true
        case .swiftStaticSdk, .customSdk: return false
        }
    }

    static func parse(_ value: String?) throws -> Self {
        guard let value else {
            return .docker
        }

        guard let method = CrossCompileMethod(rawValue: value.lowercased()) else {
            throw BuilderErrors.invalidArgument(
                "invalid cross-compile method '\(value)'. Use 'docker', 'container', 'swift-static-sdk', or 'custom-sdk'."
            )
        }

        guard method.isSupported else {
            throw BuilderErrors.unsupportedCrossCompileMethod(method)
        }

        return method
    }

    /// Creates the ``BuildBackend`` that performs a cross-compiled build for this method.
    ///
    /// Used when the host is not already an Amazon Linux machine. The configuration supplies the
    /// resolved tool path, base image, and image-update preference.
    func makeBackend(configuration: BuilderConfiguration) throws -> BuildBackend {
        let cli: ContainerCLI
        switch self {
        case .docker:
            cli = DockerCLI()
        case .container:
            cli = AppleContainerCLI()
        case .swiftStaticSdk, .customSdk:
            throw BuilderErrors.unsupportedCrossCompileMethod(self)
        }
        return ContainerBuildBackend(
            cli: cli,
            toolPath: configuration.crossCompileToolPath,
            baseImage: configuration.baseDockerImage,
            disableImageUpdate: configuration.disableDockerImageUpdate,
            method: self
        )
    }

    var description: String {
        self.rawValue
    }
}
