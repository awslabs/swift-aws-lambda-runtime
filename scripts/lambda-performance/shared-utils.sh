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

# Shared utility functions for Lambda measurement scripts

# Deploy or update a Lambda function
# Arguments: function_name, zip_file, runtime, handler, role_arn
deploy_function() {
    local function_name=$1
    local zip_file=$2
    local runtime=$3
    local handler=$4
    local role_arn=$5
    
    echo "Deploying function: $function_name"
    
    # Check if function exists
    if aws lambda get-function --function-name "$function_name" &>/dev/null; then
        echo "Function exists, updating code..."
        # Update existing function
        aws lambda update-function-code \
            --function-name "$function_name" \
            --zip-file "fileb://$zip_file" \
            > /dev/null
    else
        echo "Function does not exist, creating..."
        # Create new function with arm64 architecture
        aws lambda create-function \
            --function-name "$function_name" \
            --runtime "$runtime" \
            --role "$role_arn" \
            --handler "$handler" \
            --architectures arm64 \
            --zip-file "fileb://$zip_file" \
            > /dev/null
    fi
    
    # Wait for function to be active
    echo "Waiting for function to be active..."
    aws lambda wait function-active --function-name "$function_name"
    echo "Function deployed successfully"
}

# Invoke Lambda function and extract duration from LogResult
# Arguments: function_name, event_payload, metric_type ("cold" or "warm")
# Returns: duration in milliseconds
invoke_and_get_duration() {
    local function_name=$1
    local event_payload=$2
    local metric_type=$3  # "cold" or "warm"
    local output_file="/tmp/lambda-response-$.json"
    
    # Invoke function with --log-type Tail to get logs in response
    local encoded_payload
    encoded_payload=$(echo "$event_payload" | base64)
    aws lambda invoke \
        --function-name "$function_name" \
        --payload "$encoded_payload" \
        --log-type Tail \
        "$output_file" > /tmp/invoke-response-$.json 2>/dev/null
    
    # Extract and decode LogResult (base64-encoded logs)
    local log_result
    log_result=$(jq -r '.LogResult // empty' /tmp/invoke-response-$.json 2>/dev/null | base64 -d 2>/dev/null)
    
    # Parse the REPORT line to extract timing using sed (BSD-compatible)
    local duration=""
    if [ "$metric_type" == "cold" ]; then
        # Extract Init Duration for cold starts
        duration=$(echo "$log_result" | grep "^REPORT" | sed -n 's/.*Init Duration: \([0-9.]*\) ms.*/\1/p' | head -1)
    else
        # Extract Duration for warm starts (match first Duration, not Init Duration)
        duration=$(echo "$log_result" | grep "^REPORT" | sed -n 's/.*Duration: \([0-9.]*\) ms.*/\1/p' | head -1)
    fi
    
    # Clean up temp files
    rm -f "$output_file" /tmp/invoke-response-$.json
    
    # Return duration or 0 if not found
    if [ -z "$duration" ]; then
        echo "0"
    else
        echo "$duration"
    fi
}

# Force a cold start by updating environment variable
# Arguments: function_name
force_cold_start() {
    local function_name=$1
    local timestamp
    timestamp=$(date +%s)
    
    # Update environment variable to force new execution environment
    aws lambda update-function-configuration \
        --function-name "$function_name" \
        --environment "Variables={FORCE_COLD_START=$timestamp}" \
        > /dev/null 2>&1
    
    # Wait for update to complete
    aws lambda wait function-updated --function-name "$function_name"
    
    # Additional wait to ensure environment is recycled
    sleep 2
}

# Calculate and display statistics for measurements
# Arguments: array of duration measurements
calculate_statistics() {
    local measurements=("$@")
    local count=${#measurements[@]}
    
    if [ "$count" -eq 0 ]; then
        echo "No measurements to calculate"
        return
    fi
    
    local sum=0
    local min=${measurements[0]}
    local max=${measurements[0]}
    
    for duration in "${measurements[@]}"; do
        sum=$(echo "$sum + $duration" | bc)
        if (( $(echo "$duration < $min" | bc -l) )); then
            min=$duration
        fi
        if (( $(echo "$duration > $max" | bc -l) )); then
            max=$duration
        fi
    done
    
    local avg
    avg=$(echo "scale=2; $sum / $count" | bc)
    
    echo ""
    echo "=== Statistics ==="
    echo "  Count: $count"
    echo "  Average: ${avg}ms"
    echo "  Min: ${min}ms"
    echo "  Max: ${max}ms"
}

# Parse command-line arguments
# Sets global variables for script configuration
parse_arguments() {
    # Default values
    RUNTIME="${RUNTIME:-provided.al2023}"
    ITERATIONS="${ITERATIONS:-10}"
    FUNCTION_NAME="${FUNCTION_NAME:-lambda-perf-test}"
    HANDLER="${HANDLER:-bootstrap}"
    # a simple String payload to use with the HelloWorld function 
    EVENT_PAYLOAD="${EVENT_PAYLOAD:-\"Performance test\"}"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --zip-file)
                ZIP_FILE="$2"
                shift 2
                ;;
            --runtime)
                RUNTIME="$2"
                shift 2
                ;;
            --iterations)
                ITERATIONS="$2"
                shift 2
                ;;
            --event-file)
                EVENT_FILE="$2"
                shift 2
                ;;
            --function-name)
                FUNCTION_NAME="$2"
                shift 2
                ;;
            --handler)
                HANDLER="$2"
                shift 2
                ;;
            --role-arn)
                ROLE_ARN="$2"
                shift 2
                ;;
            *)
                echo "Unknown option: $1" >&2
                return 1
                ;;
        esac
    done
}

# Validate required parameters and dependencies
validate_parameters() {
    local errors=0
    
    # Check required parameters
    if [ -z "$ZIP_FILE" ]; then
        echo "ERROR: --zip-file is required" >&2
        errors=$((errors + 1))
    fi
    
    if [ -z "$ROLE_ARN" ]; then
        echo "ERROR: --role-arn is required" >&2
        errors=$((errors + 1))
    fi
    
    # Validate ZIP file exists
    if [ -n "$ZIP_FILE" ] && [ ! -f "$ZIP_FILE" ]; then
        echo "ERROR: ZIP file not found: $ZIP_FILE" >&2
        errors=$((errors + 1))
    fi
    
    # Handle event payload from file or use default
    if [ -n "$EVENT_FILE" ]; then
        if [ ! -f "$EVENT_FILE" ]; then
            echo "ERROR: Event file not found: $EVENT_FILE" >&2
            errors=$((errors + 1))
        else
            EVENT_PAYLOAD=$(cat "$EVENT_FILE")
        fi
    fi
    
    # Check for required tools
    if ! command -v aws &> /dev/null; then
        echo "ERROR: AWS CLI is not installed or not in PATH" >&2
        errors=$((errors + 1))
    fi
    
    if ! command -v jq &> /dev/null; then
        echo "ERROR: jq is not installed or not in PATH" >&2
        errors=$((errors + 1))
    fi
    
    if ! command -v bc &> /dev/null; then
        echo "ERROR: bc is not installed or not in PATH" >&2
        errors=$((errors + 1))
    fi
    
    return $errors
}
