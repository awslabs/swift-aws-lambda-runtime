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
# integration-test.sh
#
# End-to-end integration test for the Lambda v4 plugin system.
# Exercises the full lifecycle: scaffold → build → deploy → validate → delete.
#
# Prerequisites:
#   - AWS credentials configured (via aws configure or environment variables)
#   - Docker installed and running
#   - Swift toolchain installed
#   - curl with --aws-sigv4 support (curl 7.75+)
#
# Usage:
#   ./scripts/integration-test.sh
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

FUNCTION_NAME="swift-lambda-e2e-test-$(date +%s)"
AWS_REGION="us-east-1"
CLEANUP_NEEDED=false
WORK_DIR=""
FIXED_WORK_DIR=""

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

log() { printf -- "** %s\n" "$*" >&2; }
error() { printf -- "** ERROR: %s\n" "$*" >&2; }
fatal() { error "$@"; exit 1; }

# ---------------------------------------------------------------------------
# Cleanup (guaranteed via trap)
# ---------------------------------------------------------------------------

cleanup() {
    local exit_code=$?

    if [ "$CLEANUP_NEEDED" = true ]; then
        log "Cleaning up AWS resources for function: ${FUNCTION_NAME}..."
        (
            cd "${WORK_DIR}" && \
            swift package --allow-network-connections all:443 \
                lambda-deploy --allow-writing-to-package-directory \
                --region "${AWS_REGION}" --delete --products "${FUNCTION_NAME}" 2>&1
        ) || log "Warning: cleanup of AWS resources may have been incomplete."
    fi

    if [ -n "${WORK_DIR}" ] && [ -d "${WORK_DIR}" ] && [ -z "${FIXED_WORK_DIR}" ]; then
        log "Removing temporary directory: ${WORK_DIR}"
        rm -rf "${WORK_DIR}"
    fi

    if [ $exit_code -ne 0 ]; then
        error "Integration test FAILED (exit code: ${exit_code})"
    fi

    exit $exit_code
}

trap cleanup EXIT

# ---------------------------------------------------------------------------
# Prerequisites check
# ---------------------------------------------------------------------------

check_prerequisites() {
    log "Checking prerequisites..."

    if ! command -v swift &> /dev/null; then
        fatal "Swift toolchain not found. Please install Swift."
    fi

    if ! command -v docker &> /dev/null; then
        fatal "Docker not found. Please install Docker."
    fi

    if ! command -v curl &> /dev/null; then
        fatal "curl not found. Please install curl."
    fi

    if ! command -v aws &> /dev/null; then
        fatal "AWS CLI not found. Please install and configure the AWS CLI."
    fi

    # Verify AWS credentials are available
    if ! aws sts get-caller-identity &> /dev/null; then
        fatal "AWS credentials not configured or invalid. Run 'aws configure' or set environment variables."
    fi

    log "All prerequisites satisfied."
}

# ---------------------------------------------------------------------------
# Step 1: Create temporary project directory and initialize Swift package
# ---------------------------------------------------------------------------

scaffold_project() {
    log "Step 1: Creating temporary project directory..."

    if [ -n "${FIXED_WORK_DIR}" ]; then
        WORK_DIR="${FIXED_WORK_DIR}"
        mkdir -p "${WORK_DIR}"
        log "  Using fixed working directory: ${WORK_DIR}"

        # If Package.swift already exists, skip scaffolding
        if [ -f "${WORK_DIR}/Package.swift" ]; then
            log "  Package.swift already exists, skipping scaffold."
            cd "${WORK_DIR}"
            return
        fi
    else
        WORK_DIR=$(mktemp -d -t "swift-lambda-e2e-XXXXXX")
        log "  Working directory: ${WORK_DIR}"
    fi

    cd "${WORK_DIR}"

    # Initialize a Swift package with the function name as the executable target
    swift package init --type executable --name "${FUNCTION_NAME}"

    # Add macOS 15 platform requirement (needed by AWSLambdaRuntime)
    # Use -i.bak (works on both BSD/macOS and GNU/Linux sed) and remove the backup.
    sed -i.bak 's/name: "'"${FUNCTION_NAME}"'",/name: "'"${FUNCTION_NAME}"'",\n    platforms: [.macOS(.v15)],/' Package.swift
    rm -f Package.swift.bak

    # Add the lambda runtime dependency
    swift package add-dependency https://github.com/swift-server/swift-aws-lambda-runtime.git --branch sebsto/new-plugins
    swift package add-target-dependency AWSLambdaRuntime "${FUNCTION_NAME}" --package swift-aws-lambda-runtime

    # Also add AWSLambdaEvents for the URL template
    swift package add-dependency https://github.com/swift-server/swift-aws-lambda-events.git --branch main
    swift package add-target-dependency AWSLambdaEvents "${FUNCTION_NAME}" --package swift-aws-lambda-events

    log "  Swift package initialized."
}

# ---------------------------------------------------------------------------
# Step 2: Scaffold the Lambda function using lambda-init --with-url
# ---------------------------------------------------------------------------

scaffold_function() {
    log "Step 2: Scaffolding Lambda function with URL template..."

    cd "${WORK_DIR}"

    # Skip if already scaffolded (for --work-dir reuse)
    if [ -n "${FIXED_WORK_DIR}" ] && grep -q "LambdaRuntime" Sources/main.swift 2>/dev/null; then
        log "  Function already scaffolded, skipping."
        return
    fi

    swift package --allow-writing-to-package-directory lambda-init --with-url

    log "  Function scaffolded with URL template."
}

# ---------------------------------------------------------------------------
# Step 3: Build and package the Lambda function
# ---------------------------------------------------------------------------

build_function() {
    log "Step 3: Building and packaging the Lambda function..."

    cd "${WORK_DIR}"

    # Skip build if archive already exists (for --work-dir reuse)
    if [ -n "${FIXED_WORK_DIR}" ] && [ -d ".build/plugins/AWSLambdaBuilder/outputs" ]; then
        log "  Build artifacts found, skipping build."
        return
    fi

    swift package --allow-network-connections docker lambda-build --products "${FUNCTION_NAME}"

    log "  Build and packaging complete."
}

# ---------------------------------------------------------------------------
# Step 4: Deploy the Lambda function with Function URL
# ---------------------------------------------------------------------------

deploy_function() {
    log "Step 4: Deploying Lambda function with Function URL..."

    cd "${WORK_DIR}"

    # Capture deploy output to extract the Function URL
    DEPLOY_OUTPUT=$(swift package --allow-network-connections all:443 \
        lambda-deploy --allow-writing-to-package-directory \
        --region "${AWS_REGION}" --with-url --products "${FUNCTION_NAME}" 2>&1) || {
        error "Deployment failed."
        echo "${DEPLOY_OUTPUT}" >&2
        exit 1
    }

    # Mark cleanup as needed now that resources are deployed
    CLEANUP_NEEDED=true

    echo "${DEPLOY_OUTPUT}" >&2

    log "  Deployment complete."
}

# ---------------------------------------------------------------------------
# Step 5: Extract Function URL from deploy output
# ---------------------------------------------------------------------------

extract_function_url() {
    log "Step 5: Extracting Function URL from deploy output..."

    # The deploy plugin outputs the Function URL — extract it
    FUNCTION_URL=$(echo "${DEPLOY_OUTPUT}" | grep -oE 'https://[a-z0-9]+\.lambda-url\.[a-z0-9-]+\.on\.aws/?' | head -1)

    if [ -z "${FUNCTION_URL}" ]; then
        fatal "Could not extract Function URL from deploy output."
    fi

    log "  Function URL: ${FUNCTION_URL}"
}

# ---------------------------------------------------------------------------
# Step 6: Validate the deployed function via curl with AWS SigV4
# ---------------------------------------------------------------------------

validate_function() {
    log "Step 6: Validating deployed function via Function URL..."

    # Use the hardcoded region for SigV4 signing
    local region="${AWS_REGION}"
    log "  Region for SigV4 signing: ${region}"

    # Resolve AWS credentials for curl (supports SSO, assumed roles, config files, etc.)
    log "  Resolving AWS credentials for curl..."
    eval "$(aws configure export-credentials --format env-no-export 2>/dev/null)" || \
        fatal "Could not resolve AWS credentials. Ensure 'aws configure export-credentials' works."

    local access_key_id="${AWS_ACCESS_KEY_ID:-}"
    local secret_access_key="${AWS_SECRET_ACCESS_KEY:-}"
    local session_token="${AWS_SESSION_TOKEN:-}"

    if [ -z "${access_key_id}" ] || [ -z "${secret_access_key}" ]; then
        fatal "Could not resolve AWS credentials for curl signing."
    fi

    log "  AWS_ACCESS_KEY_ID: ${access_key_id:0:8}..."
    log "  AWS_SESSION_TOKEN: ${session_token:+present}"

    # Wait for the function to become active (cold start may take a moment)
    log "  Waiting for function to become active..."
    local max_retries=30
    local retry_count=0
    local response=""

    while [ $retry_count -lt $max_retries ]; do
        # Use curl with AWS SigV4 to call the Function URL
        response=$(curl --silent --show-error --max-time 60 \
            --aws-sigv4 "aws:amz:${region}:lambda" \
            --user "${access_key_id}:${secret_access_key}" \
            ${session_token:+-H "x-amz-security-token: ${session_token}"} \
            "${FUNCTION_URL}?name=World" 2>&1) || true

        # Check if we got the expected successful response
        if echo "${response}" | grep -q '"Hello'; then
            break
        fi

        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $max_retries ]; then
            log "  Attempt ${retry_count}/${max_retries} - waiting 10 seconds..."
            sleep 10
        fi
    done

    if [ $retry_count -ge $max_retries ]; then
        error "Function did not return a valid response after ${max_retries} attempts."
        error "Last response: ${response}"
        exit 1
    fi

    log "  Response received: ${response}"

    RESPONSE_BODY="${response}"
}

# ---------------------------------------------------------------------------
# Step 7: Verify response matches expected output
# ---------------------------------------------------------------------------

verify_response() {
    log "Step 7: Verifying response body..."

    local expected_message="Hello World"

    if echo "${RESPONSE_BODY}" | grep -q "${expected_message}"; then
        log "  Response verification PASSED: contains '${expected_message}'"
    else
        error "Response verification FAILED."
        error "  Expected response to contain: '${expected_message}'"
        error "  Actual response: '${RESPONSE_BODY}'"
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Step 8: Delete the deployed function and associated resources
# ---------------------------------------------------------------------------

delete_function() {
    log "Step 8: Deleting Lambda function and associated resources..."

    cd "${WORK_DIR}"
    swift package --allow-network-connections all:443 \
        lambda-deploy --allow-writing-to-package-directory \
        --region "${AWS_REGION}" --delete --products "${FUNCTION_NAME}"

    CLEANUP_NEEDED=false

    log "  Function and resources deleted."
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    # Parse arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            --work-dir)
                FIXED_WORK_DIR="$2"
                shift 2
                ;;
            *)
                fatal "Unknown argument: $1. Usage: $0 [--work-dir <path>]"
                ;;
        esac
    done

    log "=========================================="
    log "Lambda Plugin End-to-End Integration Test"
    log "=========================================="
    log ""
    log "Function name: ${FUNCTION_NAME}"
    log "Region: ${AWS_REGION}"
    if [ -n "${FIXED_WORK_DIR}" ]; then
        log "Fixed work dir: ${FIXED_WORK_DIR} (temp dir will NOT be deleted)"
    fi
    log ""

    check_prerequisites
    scaffold_project
    scaffold_function
    build_function
    deploy_function
    extract_function_url
    validate_function
    verify_response
    delete_function

    log ""
    log "=========================================="
    log "Integration test PASSED"
    log "=========================================="
}

main "$@"
