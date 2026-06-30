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

import AWSLambdaRuntime

// This example is intentionally identical to HelloWorld in its logic. What differs is the
// *packaging*: it is built and deployed as an OCI container image (`--archive-format oci`)
// rather than a ZIP archive. See the README for the build and deploy commands.
let runtime = LambdaRuntime { (event: String, context: LambdaContext) in
    "Hello \(event)!"
}

try await runtime.run()
