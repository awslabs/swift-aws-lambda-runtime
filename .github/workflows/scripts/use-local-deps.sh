#!/bin/bash
##===----------------------------------------------------------------------===##
##
## This source file is part of the SwiftAWSLambdaRuntime open source project
##
## Copyright (c) 2017-2024 Apple Inc. and the SwiftAWSLambdaRuntime project authors
## Licensed under Apache License v2.0
##
## See LICENSE.txt for license information
## See CONTRIBUTORS.txt for the list of SwiftAWSLambdaRuntime project authors
##
## SPDX-License-Identifier: Apache-2.0
##
##===----------------------------------------------------------------------===##

# Rewrites Package.swift in the current directory to use the local path dependency
# instead of the remote URL. This ensures CI tests against the current branch.
#
# Usage: source this file or call it from the example directory.

set -euo pipefail

log() { printf -- "** %s\n" "$*" >&2; }

log "Switching swift-aws-lambda-runtime dependency to local path"
sed -i \
  -e 's|// *\.package(name: "swift-aws-lambda-runtime", path: "\.\./\.\.")|.package(name: "swift-aws-lambda-runtime", path: "../..")|' \
  -e 's|\.package(url: "https://github.com/awslabs/swift-aws-lambda-runtime\.git", from: "[^"]*")|// .package(url: "https://github.com/awslabs/swift-aws-lambda-runtime.git", from: "0.0.0")|' \
  Package.swift
