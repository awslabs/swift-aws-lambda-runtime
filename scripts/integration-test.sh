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
CLEANUP_NEEDED=false
WORK_DIR=""

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
                --delete --products "${FUNCTION_NAME}" 2>&1
        ) || log "Warning: cleanup of AWS resources may have been incomplete."
    fi

    if [ -n "${WORK_DIR}" ] && [ -d "${WORK_DIR}" ]; then
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

    WORK_DIR=$(mktemp -d -t "swift-lambda-e2e-XXXXXX")
    log "  Working directory: ${WORK_DIR}"

    cd "${WORK_DIR}"

    # Initialize a Swift package with the function name as the executable target
    swift package init --type executable --name "${FUNCTION_NAME}"

    # Add the lambda runtime dependency
    swift package add-dependency https://github.com/swift-server/swift-aws-lambda-runtime.git --branch main
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
    swift package --allow-writing-to-package-directory lambda-init --with-url

    log "  Function scaffolded with URL template."
}

# ---------------------------------------------------------------------------
# Step 3: Build and package the Lambda function
# ---------------------------------------------------------------------------

build_function() {
    log "Step 3: Building and packaging the Lambda function..."

    cd "${WORK_DIR}"
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
        --with-url --products "${FUNCTION_NAME}" 2>&1) || {
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

    # Resolve the AWS region for signing
    local region
    region=$(aws configure get region 2>/dev/null || echo "${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}")

    # Wait for the function to become active (cold start may take a moment)
    log "  Waiting for function to become active..."
    local max_retries=30
    local retry_count=0
    local response=""

    while [ $retry_count -lt $max_retries ]; do
        # Use curl with AWS SigV4 to call the Function URL
        response=$(curl --silent --show-error --max-time 30 \
            --aws-sigv4 "aws:amz:${region}:lambda" \
            --user "${AWS_ACCESS_KEY_ID:-$(aws configure get aws_access_key_id)}:${AWS_SECRET_ACCESS_KEY:-$(aws configure get aws_secret_access_key)}" \
            ${AWS_SESSION_TOKEN:+-H "x-amz-security-token: ${AWS_SESSION_TOKEN}"} \
            "${FUNCTION_URL}?name=World" 2>&1) || true

        # Check if we got a valid response (not a 5xx or connection error)
        if echo "${response}" | grep -q '"message"'; then
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
        --delete --products "${FUNCTION_NAME}"

    CLEANUP_NEEDED=false

    log "  Function and resources deleted."
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    log "=========================================="
    log "Lambda Plugin End-to-End Integration Test"
    log "=========================================="
    log ""
    log "Function name: ${FUNCTION_NAME}"
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
