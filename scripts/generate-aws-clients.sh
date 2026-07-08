#!/bin/bash
##===----------------------------------------------------------------------===##
##
## This source file is part of the SwiftAWSLambdaRuntime open source project
##
## Copyright SwiftAWSLambdaRuntime project authors
## Copyright (c) Amazon.com, Inc. or its affiliates.
## Licensed under Apache License v2.0
##
## See LICENSE.txt for license information
## See CONTRIBUTORS.txt for the list of SwiftAWSLambdaRuntime project authors
##
## SPDX-License-Identifier: Apache-2.0
##
##===----------------------------------------------------------------------===##

# =============================================================================
# generate-aws-clients.sh
#
# Maintainer-run script to generate AWS service clients for the Lambda deploy
# plugin. This script is NOT part of the build process. It generates lightweight
# Swift clients for Lambda, IAM, S3, STS, and ECR with only the operations
# required by the deployer.
#
# How it works
# ------------
# Rather than driving the Soto Code Generator binary directly (whose CLI changes
# between releases), this script scaffolds a *throwaway* SwiftPM project that uses
# the two Soto plugins, with a single `soto.config.json` as the source of truth:
#
#   1. `swift package plugin download-aws-models` reads the services listed in
#      soto.config.json and downloads their Smithy models (from aws/api-models-aws)
#      into the target's `aws-models/` folder.
#   2. `swift build` runs the SotoCodeGeneratorPlugin build-tool plugin, which emits
#      `<service>_api.swift` / `<service>_shapes.swift` into the build output.
#
# The script then copies those files into `GeneratedClients/<Service>/`, prepends
# the project license header, and inserts the `@available(LambdaSwift 2.0, *)`
# macro the package requires.
#
# The throwaway project is created under a temporary directory and removed on
# exit, so nothing but the generated clients is left behind.
#
# Prerequisites:
#   - Swift toolchain (the same one used to build the package)
#   - Internet access (to resolve the codegen/soto-core packages and download
#     the AWS Smithy models)
#
# Usage:
#   ./scripts/generate-aws-clients.sh
#
# Compatible with the stock macOS Bash 3.2 (no associative arrays / Bash 4+
# features are used).
# =============================================================================

set -euo pipefail

log() { printf -- "** %s\n" "$*" >&2; }
error() { printf -- "** ERROR: %s\n" "$*" >&2; }
fatal() { error "$@"; exit 1; }

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUTPUT_DIR="${PROJECT_ROOT}/Sources/AWSLambdaPluginHelper/GeneratedClients"

# Pinned plugin / soto-core versions (the plugin pulls in the generator).
SOTO_CODEGEN_VERSION="7.9.3"
SOTO_CORE_VERSION="7.14.0"

# soto.config.json - the single source of truth for what gets generated. Both Soto
# plugins read it: `download-aws-models` downloads exactly the services listed (keyed
# by their lowercase model name in aws/api-models-aws), and the codegen plugin emits
# only the listed operations.
#
# IMPORTANT: operation names MUST be camelCase (lowercase first letter); PascalCase
# matches nothing and silently emits an empty client.
SOTO_CONFIG_JSON='{
    "access": "public",
    "services": {
        "lambda": { "operations": ["createFunction","updateFunctionCode","deleteFunction","getFunction","createFunctionUrlConfig","getFunctionUrlConfig","deleteFunctionUrlConfig","addPermission","removePermission"] },
        "iam": { "operations": ["createRole","deleteRole","attachRolePolicy","detachRolePolicy","getRole","putRolePolicy","deleteRolePolicy"] },
        "s3": { "operations": ["createBucket","headBucket","putObject","deleteObject"] },
        "sts": { "operations": ["getCallerIdentity"] },
        "ecr": { "operations": ["getAuthorizationToken","createRepository","describeRepositories","getRepositoryPolicy","setRepositoryPolicy","batchGetImage"] }
    }
}'

# Maps each lowercase model name (the generated <model>_*.swift prefix) to its PascalCase
# GeneratedClients/<Service>/ directory. Space-separated "model:Service" pairs - no
# associative arrays, so this runs on the stock macOS Bash 3.2.
SERVICE_DIRS="lambda:Lambda iam:IAM s3:S3 sts:STS ecr:ECR"

# Working directory for the throwaway generation project. Removed on exit.
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/soto-codegen.XXXXXX")"
GEN_PROJECT="${WORK_DIR}/SotoClientGen"

cleanup() {
    rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

check_prerequisites() {
    log "Checking prerequisites..."
    command -v swift > /dev/null 2>&1 || fatal "Swift toolchain not found. Please install Swift."
    log "Prerequisites satisfied."
}

scaffold_project() {
    log "Scaffolding throwaway generation project at ${GEN_PROJECT}..."

    local sources="${GEN_PROJECT}/Sources/SotoClientGen"
    mkdir -p "${sources}"

    cat > "${GEN_PROJECT}/Package.swift" << EOF
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "SotoClientGen",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/soto-project/soto-codegenerator", from: "${SOTO_CODEGEN_VERSION}"),
        .package(url: "https://github.com/soto-project/soto-core.git", from: "${SOTO_CORE_VERSION}"),
    ],
    targets: [
        .target(
            name: "SotoClientGen",
            dependencies: [.product(name: "SotoCore", package: "soto-core")],
            plugins: [.plugin(name: "SotoCodeGeneratorPlugin", package: "soto-codegenerator")]
        )
    ]
)
EOF

    # SwiftPM only runs build-tool plugins on a target that has at least one source file.
    echo "// Placeholder so SwiftPM treats this as a source module and runs the codegen plugin." \
        > "${sources}/Placeholder.swift"

    # The config is the single source of truth for both Soto plugins (download + codegen).
    printf '%s\n' "${SOTO_CONFIG_JSON}" > "${sources}/soto.config.json"

    log "Project scaffolded."
}

download_models() {
    log "Downloading AWS service models via the download-aws-models plugin..."
    # The plugin reads soto.config.json and writes <target>/aws-models/<service>.json
    # (plus endpoints.json), which the codegen build-tool plugin then consumes.
    ( cd "${GEN_PROJECT}" && swift package plugin \
        --allow-writing-to-package-directory \
        --allow-network-connections all:443 \
        download-aws-models 2>&1 | sed 's/^/    /' )
    log "AWS service models downloaded."
}

run_codegen() {
    log "Running the Soto Code Generator plugin (this resolves packages and builds)..."
    ( cd "${GEN_PROJECT}" && swift build 2>&1 | sed 's/^/    /' )
    log "Code generation complete."
}

# Locate the plugin's GeneratedSources directory inside the throwaway project's .build tree.
generated_sources_dir() {
    find "${GEN_PROJECT}/.build" -type d -name GeneratedSources -path '*SotoCodeGeneratorPlugin*' \
        2>/dev/null | head -1
}

# The license header expected by check-license.sh, rendered for Swift files.
license_header() {
    cat << 'EOF'
//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftAWSLambdaRuntime open source project
//
// Copyright SwiftAWSLambdaRuntime project authors
// Copyright (c) Amazon.com, Inc. or its affiliates.
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftAWSLambdaRuntime project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

// Generated by scripts/generate-aws-clients.sh - DO NOT EDIT
EOF
}

# Post-process one generated file in place: prepend the license header, insert
# `@available(LambdaSwift 2.0, *)` before each top-level public/extension declaration,
# and apply ExistentialAny / InternalImportsByDefault fixes.
#
# The package does not declare a platforms: floor, but soto-core's types carry an
# availability annotation, so every top-level declaration in the generated code must
# match it. We add the macro before column-0 `public struct/enum/...` and `extension`
# lines (top-level only - nested members are already covered by their enclosing type).
postprocess_file() {
    local src="$1" dest="$2"
    {
        license_header
        echo ""
        awk '
            # Strip the generator-supplied leading license banner so it is not duplicated
            # below ours: skip the first comment block (the //===...===// banner and the
            # lines between, plus any blank lines that follow it).
            BEGIN { in_banner = 1 }
            in_banner {
                if ($0 ~ /^\/\// || $0 ~ /^[[:space:]]*$/) { next }
                in_banner = 0
            }
            # Insert the availability macro before each top-level declaration.
            /^(public[ ]+(struct|enum|final[ ]+class|class|actor|protocol)|extension)[ ]/ {
                print "@available(LambdaSwift 2.0, *)"
            }
            { print }
        ' "${src}"
    } > "${dest}"

    # --- ExistentialAny fixes ---
    # Wrap optional protocol types with `any` (e.g. AWSMiddlewareProtocol? -> (any AWSMiddlewareProtocol)?)
    sed -i '' 's/middleware: AWSMiddlewareProtocol?/middleware: (any AWSMiddlewareProtocol)?/g' "${dest}"
    # Encoder/Decoder in function signatures
    sed -i '' 's/encoder: Encoder)/encoder: any Encoder)/g' "${dest}"
    sed -i '' 's/decoder: Decoder)/decoder: any Decoder)/g' "${dest}"

    # --- InternalImportsByDefault fixes  ---
    # Files that expose Foundation types (e.g. Date) in public API need public imports.
    # Check for Date in public properties OR in @inlinable function parameters.
    if grep -q 'public.*let.*: Date' "${dest}" || \
       grep -q 'public.*var.*: Date' "${dest}" || \
       grep -q ': Date?' "${dest}"; then
        local tmp="${dest}.tmp"
        awk '
        /^#if canImport\(FoundationEssentials\)$/ {
            print "#if canImport(FoundationEssentials)"
            print "public import FoundationEssentials"
            print "#else"
            print "public import Foundation"
            print "#endif"
            # Skip the original 4 lines (#if, import, #else, import, #endif)
            getline; getline; getline; getline
            next
        }
        { print }
        ' "${dest}" > "${tmp}" && mv "${tmp}" "${dest}"
    fi
}

copy_and_postprocess() {
    log "Installing generated clients into ${OUTPUT_DIR}..."

    local gen_dir
    gen_dir="$(generated_sources_dir)"
    [ -n "${gen_dir}" ] || fatal "could not locate generated sources under ${GEN_PROJECT}/.build"

    rm -rf "${OUTPUT_DIR}"
    mkdir -p "${OUTPUT_DIR}"

    for pair in ${SERVICE_DIRS}; do
        local model_name="${pair%%:*}"
        local service="${pair##*:}"
        local dest_dir="${OUTPUT_DIR}/${service}"
        mkdir -p "${dest_dir}"

        local found=0
        for suffix in api shapes; do
            local src="${gen_dir}/${model_name}_${suffix}.swift"
            if [ -f "${src}" ]; then
                postprocess_file "${src}" "${dest_dir}/${service}_${suffix}.swift"
                found=1
            fi
        done
        [ "${found}" -eq 1 ] || fatal "no generated files found for ${service} (looked for ${model_name}_*.swift in ${gen_dir})"
        log "  Installed ${service} client"
    done

    log "Formatting generated clients..."
    swift format format --parallel --in-place --recursive "${OUTPUT_DIR}" 2>/dev/null || \
        log "  (swift format not available or failed; run 'swift format' manually if needed)"

    log "Generated clients installed at ${OUTPUT_DIR}"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    log "=========================================="
    log "AWS Service Client Generation"
    log "=========================================="
    log ""
    log "Output:   ${OUTPUT_DIR}"
    log ""

    check_prerequisites
    scaffold_project
    download_models
    run_codegen
    copy_and_postprocess

    log ""
    log "Done. Review the diff under ${OUTPUT_DIR}, then 'swift build' to verify."
}

main "$@"
