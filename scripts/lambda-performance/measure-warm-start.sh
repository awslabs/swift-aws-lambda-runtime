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

set -e

# Warm Start Measurement Script
# Measures Lambda warm start times (Duration) by reusing the same execution environment

# Source shared utility functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lambda-performance/shared-utils.sh
source "$SCRIPT_DIR/shared-utils.sh"

# Parse command-line arguments
parse_arguments "$@"

# Validate required parameters and dependencies
if ! validate_parameters; then
    echo ""
    echo "Usage: $0 --zip-file <path> --role-arn <arn> [options]"
    echo ""
    echo "Required:"
    echo "  --zip-file <path>       Path to Lambda deployment package (ZIP file)"
    echo "  --role-arn <arn>        IAM role ARN for Lambda execution"
    echo ""
    echo "Optional:"
    echo "  --runtime <runtime>     Lambda runtime (default: provided.al2023)"
    echo "  --iterations <n>        Number of measurements (default: 10)"
    echo "  --event-file <path>     Path to JSON event payload file"
    echo "  --function-name <name>  Lambda function name (default: lambda-perf-test)"
    echo "  --handler <handler>     Lambda handler (default: bootstrap)"
    echo ""
    exit 1
fi

echo "=== Warm Start Measurement ==="
echo "Function: $FUNCTION_NAME"
echo "Runtime: $RUNTIME"
echo "Iterations: $ITERATIONS"
echo ""

# Deploy Lambda function
deploy_function "$FUNCTION_NAME" "$ZIP_FILE" "$RUNTIME" "$HANDLER" "$ROLE_ARN"

echo ""
echo "=== Warming Up Function ==="
echo "Making initial invocation to warm up execution environment..."
echo ""

# Make initial warm-up call (this will be a cold start, so we discard it)
warmup_duration=$(invoke_and_get_duration "$FUNCTION_NAME" "$EVENT_PAYLOAD" "warm")
if [ "$warmup_duration" != "0" ] && [ -n "$warmup_duration" ]; then
    echo "Warm-up complete (Duration: ${warmup_duration}ms)"
else
    echo "WARNING: Warm-up invocation completed but duration not captured"
fi

echo ""
echo "=== Starting Measurements ==="
echo ""

# Array to store measurements
measurements=()

# Measurement loop for N iterations (all should be warm starts now)
for i in $(seq 1 "$ITERATIONS"); do
    echo "Iteration $i/$ITERATIONS"
    
    # Invoke function with metric_type="warm" to get Duration (no cold start forcing)
    duration=$(invoke_and_get_duration "$FUNCTION_NAME" "$EVENT_PAYLOAD" "warm")
    
    if [ "$duration" == "0" ] || [ -z "$duration" ]; then
        echo "  WARNING: Failed to get Duration, skipping measurement" >&2
    else
        echo "  Duration: ${duration}ms"
        measurements+=("$duration")
    fi
    
    echo ""
done

# Calculate and display statistics
echo "=== Warm Start Results ==="
calculate_statistics "${measurements[@]}"
