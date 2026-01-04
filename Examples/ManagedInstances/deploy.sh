#!/bin/bash

# Deploy script for Lambda Managed Instances example
# This script builds the Swift Lambda functions and deploys them using SAM

set -e

echo "🚀 Building Swift Lambda functions for Managed Instances..."

# Build all targets
LAMBDA_USE_LOCAL_DEPS=../.. swift package archive --allow-network-connections docker --disable-docker-image-update

echo "📦 Packaging complete. Deploying to AWS..."

# Change the values below to match your setup 
REGION=us-west-2
CAPACITY_PROVIDER=arn:aws:lambda:us-west-2:486652066693:capacity-provider:TestEC2

# Deploy using SAM
sam deploy \
    --region ${REGION} \
    --resolve-s3 \
    --template-file template.yaml \
    --stack-name swift-lambda-managed-instances \
    --capabilities CAPABILITY_IAM \
    --region us-west-2 \
    --parameter-overrides \
        CapacityProviderArn=${CAPACITY_PROVIDER}

echo "✅ Deployment complete!"
echo ""
echo "📋 Stack outputs:"
aws cloudformation describe-stacks \
    --stack-name swift-lambda-managed-instances \
    --region ${REGION} \
    --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
    --output table
