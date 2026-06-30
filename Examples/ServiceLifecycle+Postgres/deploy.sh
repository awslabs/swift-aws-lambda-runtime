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

# ServiceLifecycle Lambda Deployment Script
set -e

echo "🚀 Building and deploying ServiceLifecycle Lambda with PostgreSQL..."

# Build the Lambda function
echo "📦 Building Swift Lambda function..."
swift package --allow-network-connections docker lambda-build 

# Deploy with SAM
echo "🌩️  Deploying with SAM..."
sam deploy

echo "✅ Deployment complete!"
echo ""
echo "📋 To get the database connection details, run:"
echo "aws cloudformation describe-stacks --stack-name servicelifecycle-stack --query 'Stacks[0].Outputs'"
echo ""
echo "🧪 To test the Lambda function:"
# shellcheck disable=SC2006,SC2016
echo "curl $(aws cloudformation describe-stacks --stack-name servicelifecycle-stack --query 'Stacks[0].Outputs[?OutputKey==`APIGatewayEndpoint`].OutputValue' --output text)"
