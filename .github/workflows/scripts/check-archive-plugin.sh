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

# This script validates the packaging plugins

set -euo pipefail

log() { printf -- "** %s\n" "$*" >&2; }
error() { printf -- "** ERROR: %s\n" "$*" >&2; }
fatal() { error "$@"; exit 1; }

test -n "${EXAMPLE:-}" || fatal "EXAMPLE unset"

# Use the local checkout of swift-aws-lambda-runtime instead of the published release
.github/workflows/scripts/use-local-deps.sh "Examples/${EXAMPLE}/Package.swift"

# The product name is "MyLambda" in both HelloWorld and ResourcesPackaging.
PRODUCT=MyLambda

pushd "Examples/${EXAMPLE}" >/dev/null || exit 1

# ---------------------------------------------------------------------------
# Assert that a given output directory contains a valid Linux bootstrap and ZIP.
# $1: human-readable label of the verb under test
# $2: path to the plugin output directory (containing <PRODUCT>/)
# ---------------------------------------------------------------------------
verify_output() {
    local label="$1"
    local output_dir="$2"
    local bootstrap="${output_dir}/${PRODUCT}/bootstrap"
    local zip_file="${output_dir}/${PRODUCT}/${PRODUCT}.zip"

    log "Verifying output of '${label}'"

    # did the plugin generate a Linux binary?
    [ -f "${bootstrap}" ] || fatal "${label}: bootstrap not found at ${bootstrap}"
    file "${bootstrap}" | grep --silent ELF || fatal "${label}: bootstrap is not an ELF binary"

    # did the plugin create a ZIP file?
    [ -f "${zip_file}" ] || fatal "${label}: ZIP not found at ${zip_file}"

    # does the ZIP file contain the bootstrap?
    unzip -l "${zip_file}" | grep --silent bootstrap || fatal "${label}: bootstrap missing from ZIP"

    # if EXAMPLE is ResourcesPackaging, check the ZIP file contains hello.txt
    if [ "$EXAMPLE" == "ResourcesPackaging" ]; then
        log "${label}: checking that the resource was added to the ZIP file"
        if unzip -l "${zip_file}" | grep --silent hello.txt; then
            log "✅ ${label}: resource found."
        else
            fatal "❌ ${label}: resource hello.txt not found in ZIP."
        fi
    fi

    log "✅ ${label}: output is OK for example ${EXAMPLE}"
}

# ---------------------------------------------------------------------------
# 1. 'lambda-build' verb
# ---------------------------------------------------------------------------
log "Testing 'lambda-build' verb"
BUILD_OUTPUT_DIR=.build/plugins/AWSLambdaBuilder/outputs/AWSLambdaBuilder
LAMBDA_USE_LOCAL_DEPS=../.. swift package lambda-build \
    --allow-network-connections docker \
    --products "${PRODUCT}" \
    --base-docker-image swift:amazonlinux2023 || fatal "'lambda-build' verb failed"
verify_output "lambda-build" "${BUILD_OUTPUT_DIR}"

echo "✅ 'lambda-build' is OK with example ${EXAMPLE}"
popd >/dev/null || exit 1
