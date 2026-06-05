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
# plugin. This script is NOT part of the build process. It uses the Soto Code
# Generator to produce lightweight Swift clients for Lambda, IAM, S3, and STS
# with only the operations required by the deployer.
#
# Prerequisites:
#   - Swift toolchain installed
#   - Git installed
#   - Internet access (to clone repos and download models)
#
# Usage:
#   ./scripts/generate-aws-clients.sh
#
# The generated files are written to:
#   Sources/AWSLambdaPluginHelper/GeneratedClients/
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

# Soto Code Generator repository and version
SOTO_CODEGEN_REPO="https://github.com/soto-project/soto-codegenerator.git"
SOTO_CODEGEN_BRANCH="main"

# AWS SDK Smithy models repository
AWS_MODELS_REPO="https://github.com/aws/aws-sdk-go-v2.git"
AWS_MODELS_BRANCH="main"

# Working directory for generation
WORK_DIR="${PROJECT_ROOT}/.build/codegen-work"

# Services and their required operations
declare -A SERVICE_OPERATIONS
SERVICE_OPERATIONS=(
    ["Lambda"]="CreateFunction,UpdateFunctionCode,DeleteFunction,GetFunction,CreateFunctionUrlConfig,GetFunctionUrlConfig,DeleteFunctionUrlConfig,AddPermission,RemovePermission"
    ["IAM"]="CreateRole,DeleteRole,AttachRolePolicy,DetachRolePolicy,GetRole,PutRolePolicy,DeleteRolePolicy"
    ["S3"]="CreateBucket,HeadBucket,PutObject,DeleteObject"
    ["STS"]="GetCallerIdentity"
)

# Map service names to their Smithy model directory names in aws-sdk-go-v2
declare -A SERVICE_MODEL_DIRS
SERVICE_MODEL_DIRS=(
    ["Lambda"]="lambda"
    ["IAM"]="iam"
    ["S3"]="s3"
    ["STS"]="sts"
)

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

check_prerequisites() {
    log "Checking prerequisites..."

    if ! command -v swift &> /dev/null; then
        fatal "Swift toolchain not found. Please install Swift."
    fi

    if ! command -v git &> /dev/null; then
        fatal "Git not found. Please install git."
    fi

    log "Prerequisites satisfied."
}

setup_work_dir() {
    log "Setting up working directory at ${WORK_DIR}..."
    rm -rf "${WORK_DIR}"
    mkdir -p "${WORK_DIR}"
}

clone_codegen() {
    log "Cloning Soto Code Generator..."
    if [ -d "${WORK_DIR}/soto-codegenerator" ]; then
        log "Soto Code Generator already cloned, pulling latest..."
        git -C "${WORK_DIR}/soto-codegenerator" pull --quiet
    else
        git clone --quiet --depth 1 --branch "${SOTO_CODEGEN_BRANCH}" \
            "${SOTO_CODEGEN_REPO}" "${WORK_DIR}/soto-codegenerator"
    fi
    log "Soto Code Generator ready."
}

download_models() {
    log "Downloading AWS service model files..."

    local models_dir="${WORK_DIR}/aws-models"
    mkdir -p "${models_dir}"

    # Clone aws-sdk-go-v2 sparsely to get only the service model directories we need
    if [ ! -d "${WORK_DIR}/aws-sdk-go-v2" ]; then
        git clone --quiet --depth 1 --filter=blob:none --sparse \
            --branch "${AWS_MODELS_BRANCH}" \
            "${AWS_MODELS_REPO}" "${WORK_DIR}/aws-sdk-go-v2"

        pushd "${WORK_DIR}/aws-sdk-go-v2" > /dev/null
        local sparse_paths=""
        for service in "${!SERVICE_MODEL_DIRS[@]}"; do
            sparse_paths="${sparse_paths} codegen/sdk-codegen/aws-models/${SERVICE_MODEL_DIRS[$service]}"
        done
        # shellcheck disable=SC2086
        git sparse-checkout set ${sparse_paths}
        popd > /dev/null
    fi

    # Copy model files to our working models directory
    for service in "${!SERVICE_MODEL_DIRS[@]}"; do
        local model_dir_name="${SERVICE_MODEL_DIRS[$service]}"
        local src_dir="${WORK_DIR}/aws-sdk-go-v2/codegen/sdk-codegen/aws-models/${model_dir_name}"
        if [ -d "${src_dir}" ]; then
            cp -r "${src_dir}" "${models_dir}/"
            log "  Copied model for ${service} (${model_dir_name})"
        else
            # Try alternative model locations
            local alt_src="${WORK_DIR}/aws-sdk-go-v2/codegen/sdk-codegen/aws-models"
            local smithy_file
            smithy_file=$(find "${alt_src}" -name "${model_dir_name}.json" -o -name "${model_dir_name}.smithy" 2>/dev/null | head -1)
            if [ -n "${smithy_file}" ]; then
                mkdir -p "${models_dir}/${model_dir_name}"
                cp "${smithy_file}" "${models_dir}/${model_dir_name}/"
                log "  Copied model file for ${service}"
            else
                fatal "Could not find Smithy model for ${service} (looked in ${src_dir})"
            fi
        fi
    done

    log "AWS service models ready."
}

generate_config() {
    log "Generating code generator configuration..."

    local config_file="${WORK_DIR}/codegen-config.json"

    # Build the configuration JSON with only the operations we need
    cat > "${config_file}" << 'CONFIGEOF'
{
    "services": {
        "Lambda": {
            "operations": [
                "CreateFunction",
                "UpdateFunctionCode",
                "DeleteFunction",
                "GetFunction",
                "CreateFunctionUrlConfig",
                "GetFunctionUrlConfig",
                "DeleteFunctionUrlConfig",
                "AddPermission",
                "RemovePermission"
            ]
        },
        "IAM": {
            "operations": [
                "CreateRole",
                "DeleteRole",
                "AttachRolePolicy",
                "DetachRolePolicy",
                "GetRole",
                "PutRolePolicy",
                "DeleteRolePolicy"
            ]
        },
        "S3": {
            "operations": [
                "CreateBucket",
                "HeadBucket",
                "PutObject",
                "DeleteObject"
            ]
        },
        "STS": {
            "operations": [
                "GetCallerIdentity"
            ]
        }
    }
}
CONFIGEOF

    log "Configuration written to ${config_file}"
}

run_codegen() {
    log "Building Soto Code Generator..."
    pushd "${WORK_DIR}/soto-codegenerator" > /dev/null
    swift build --configuration release 2>&1 | tail -5
    popd > /dev/null

    log "Running code generation for each service..."

    local codegen_bin="${WORK_DIR}/soto-codegenerator/.build/release/soto-codegenerator"
    local models_dir="${WORK_DIR}/aws-models"
    local generated_dir="${WORK_DIR}/generated"
    mkdir -p "${generated_dir}"

    # If the code generator binary doesn't exist, try the default executable name
    if [ ! -f "${codegen_bin}" ]; then
        codegen_bin=$(find "${WORK_DIR}/soto-codegenerator/.build/release" -type f -perm +111 -name "*codegen*" | head -1)
        if [ -z "${codegen_bin}" ]; then
            # Fall back to running via swift run
            log "Using 'swift run' to invoke the code generator..."
            codegen_bin="SWIFT_RUN"
        fi
    fi

    for service in "${!SERVICE_MODEL_DIRS[@]}"; do
        local model_dir_name="${SERVICE_MODEL_DIRS[$service]}"
        local model_path="${models_dir}/${model_dir_name}"
        local service_output="${generated_dir}/${service}"
        mkdir -p "${service_output}"

        log "  Generating ${service} client..."

        local operations="${SERVICE_OPERATIONS[$service]}"

        if [ "${codegen_bin}" = "SWIFT_RUN" ]; then
            pushd "${WORK_DIR}/soto-codegenerator" > /dev/null
            swift run soto-codegenerator \
                --model-path "${model_path}" \
                --output-path "${service_output}" \
                --operations "${operations}" \
                --module "${service}" \
                2>&1 || log "  Warning: Code generation for ${service} returned non-zero (may need manual review)"
            popd > /dev/null
        else
            "${codegen_bin}" \
                --model-path "${model_path}" \
                --output-path "${service_output}" \
                --operations "${operations}" \
                --module "${service}" \
                2>&1 || log "  Warning: Code generation for ${service} returned non-zero (may need manual review)"
        fi
    done

    log "Code generation complete."
}

copy_output() {
    log "Copying generated clients to ${OUTPUT_DIR}..."

    local generated_dir="${WORK_DIR}/generated"

    # Clean previous generated output
    rm -rf "${OUTPUT_DIR}"
    mkdir -p "${OUTPUT_DIR}"

    for service in "${!SERVICE_MODEL_DIRS[@]}"; do
        local service_dir="${generated_dir}/${service}"
        local dest_dir="${OUTPUT_DIR}/${service}"

        if [ -d "${service_dir}" ] && [ "$(ls -A "${service_dir}" 2>/dev/null)" ]; then
            mkdir -p "${dest_dir}"
            cp -r "${service_dir}/"* "${dest_dir}/"
            log "  Copied ${service} → ${dest_dir}"
        else
            log "  Warning: No generated files found for ${service} in ${service_dir}"
            log "  You may need to create the client files manually."
        fi
    done

    log "Generated clients installed at ${OUTPUT_DIR}"
}

add_availability_annotations() {
    log "Adding @available(LambdaSwift 2.0, *) annotations..."

    # Add @available(LambdaSwift 2.0, *) before every top-level struct/enum declaration
    # in the generated files. This is required because soto-core uses availability
    # annotations on its types (AWSClient, AWSServiceConfig, etc.) and this package
    # does not declare a platforms: minimum.
    find "${OUTPUT_DIR}" -name "*.swift" -print0 | while IFS= read -r -d '' file; do
        perl -i -pe 's/^((?:public )?(?:struct|enum) \w+)/\@available(LambdaSwift 2.0, *)\n$1/' "$file"
    done

    log "Availability annotations added."
}

cleanup() {
    log "Cleaning up working directory..."
    rm -rf "${WORK_DIR}"
    log "Cleanup complete."
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    log "=========================================="
    log "AWS Service Client Generation Script"
    log "=========================================="
    log ""
    log "This script generates lightweight AWS service clients"
    log "for the Lambda deploy plugin using the Soto Code Generator."
    log ""
    log "Services: Lambda, IAM, S3, STS"
    log "Output:   ${OUTPUT_DIR}"
    log ""

    check_prerequisites
    setup_work_dir
    clone_codegen
    download_models
    generate_config
    run_codegen
    copy_output
    add_availability_annotations

    # Uncomment the following line to clean up after successful generation:
    # cleanup

    log ""
    log "=========================================="
    log "Generation complete!"
    log "=========================================="
    log ""
    log "Generated files are at:"
    log "  ${OUTPUT_DIR}"
    log ""
    log "Next steps:"
    log "  1. Review the generated files"
    log "  2. Run 'swift build' to verify compilation"
    log "  3. Commit the generated files to the repository"
    log ""
    log "Note: If the code generator did not produce the expected output,"
    log "you may need to adjust the model paths or write the client files"
    log "manually based on the Soto client patterns."
    log ""
}

main "$@"
