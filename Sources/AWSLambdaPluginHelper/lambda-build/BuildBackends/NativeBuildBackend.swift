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

/// Builds products natively on the host by invoking `/usr/bin/swift` directly.
///
/// Used when the build already runs on an Amazon Linux host, so no cross-compilation is needed.
@available(LambdaSwift 2.0, *)
struct NativeBuildBackend: BuildBackend {
    let name = "native"

    func build(
        packageIdentity: String,
        packageDirectory: URL,
        products: [String],
        buildConfiguration: BuildConfiguration,
        noStrip: Bool,
        verboseLogging: Bool
    ) throws -> [String: URL] {
        print("-------------------------------------------------------------------------")
        print("building \"\(packageIdentity)\"")
        print("-------------------------------------------------------------------------")

        var results = [String: URL]()
        for product in products {
            print("building \"\(product)\"")
            var buildArguments = [
                "build", "-c", buildConfiguration.rawValue,
                "--product", product,
                "--static-swift-stdlib",
            ]
            if !noStrip {
                buildArguments += ["-Xlinker", "-s"]
            }
            try Utils.execute(
                executable: URL(fileURLWithPath: "/usr/bin/swift"),
                arguments: buildArguments,
                logLevel: verboseLogging ? .debug : .output
            )

            // get the build output path
            let showBinPathArguments = ["build", "-c", buildConfiguration.rawValue, "--show-bin-path"]
            let binPath = try Utils.execute(
                executable: URL(fileURLWithPath: "/usr/bin/swift"),
                arguments: showBinPathArguments,
                logLevel: .silent
            ).trimmingCharacters(in: .whitespacesAndNewlines)

            let productPath = URL(fileURLWithPath: binPath).appending(path: product)
            guard FileManager.default.fileExists(atPath: productPath.path()) else {
                print("expected '\(product)' binary at \"\(productPath.path())\"")
                throw BuilderErrors.productExecutableNotFound(product)
            }
            results[product] = productPath
        }
        return results
    }
}
