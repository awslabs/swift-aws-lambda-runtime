#!/bin/bash
##===----------------------------------------------------------------------===##
##
## This source file is part of the SwiftAWSLambdaRuntime open source project
##
## Copyright (c) 2017-2018 Apple Inc. and the SwiftAWSLambdaRuntime project authors
## Licensed under Apache License v2.0
##
## See LICENSE.txt for license information
## See CONTRIBUTORS.txt for the list of SwiftAWSLambdaRuntime project authors
##
## SPDX-License-Identifier: Apache-2.0
##
##===----------------------------------------------------------------------===##

set -euo pipefail

log() { printf -- "** %s\n" "$*" >&2; }
error() { printf -- "** ERROR: %s\n" "$*" >&2; }
fatal() { error "$@"; exit 1; }

SWIFT_VERSION=$(swift --version)
test -n "${SWIFT_VERSION:-}" || fatal "SWIFT_VERSION unset"
test -n "${COMMAND:-}" || fatal "COMMAND unset"
test -n "${EXAMPLE:-}" || fatal "EXAMPLE unset"

pushd Examples/"$EXAMPLE" > /dev/null

# Use the local checkout of swift-aws-lambda-runtime instead of the published release
source "$(dirname "$0")/use-local-deps.sh"

log "Running command with Swift $SWIFT_VERSION"
eval "$COMMAND"

popd
