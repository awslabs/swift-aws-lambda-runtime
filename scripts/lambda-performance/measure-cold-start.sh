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

# Cold Start Measurement Script
# Measures Lambda cold start times (Init Duration) by forcing new execution environments

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

echo "=== Cold Start Measurement ==="
echo "Function: $FUNCTION_NAME"
echo "Runtime: $RUNTIME"
echo "Iterations: $ITERATIONS"
echo ""

# Deploy Lambda function
deploy_function "$FUNCTION_NAME" "$ZIP_FILE" "$RUNTIME" "$HANDLER" "$ROLE_ARN"

echo ""
echo "=== Starting Measurements ==="
echo ""

# Array to store measurements
measurements=()

# Measurement loop for N iterations
for i in $(seq 1 "$ITERATIONS"); do
    echo "Iteration $i/$ITERATIONS"
    
    # Invoke function with metric_type="cold" to get Init Duration
    duration=$(invoke_and_get_duration "$FUNCTION_NAME" "$EVENT_PAYLOAD" "cold")
    
    if [ "$duration" == "0" ] || [ -z "$duration" ]; then
        echo "  WARNING: Failed to get Init Duration, skipping measurement" >&2
    else
        echo "  Init Duration: ${duration}ms"
        measurements+=("$duration")
    fi
    
    # Force cold start for next iteration (except on last iteration)
    if [ "$i" -lt "$ITERATIONS" ]; then
        echo "  Forcing cold start..."
        force_cold_start "$FUNCTION_NAME"
    fi
    
    echo ""
done

# Calculate and display statistics
echo "=== Cold Start Results ==="
calculate_statistics "${measurements[@]}"
