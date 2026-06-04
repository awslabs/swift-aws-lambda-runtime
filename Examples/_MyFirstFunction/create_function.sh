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

# Stop the script execution if an error occurs
set -e -o pipefail

# check if docker is installed
which docker > /dev/null || (echo "Docker is not installed. Please install Docker and try again." && exit 1)

# check if aws cli is installed
which aws > /dev/null || (echo "AWS CLI is not installed. Please install AWS CLI and try again." && exit 1)

echo "This script creates, builds, deploys, and invokes a Lambda function on your AWS Account.

You must have an AWS account and have run 'aws configure' to set up your credentials in ~/.aws/.
"

printf "Are you ready to create your first Lambda function in Swift? [y/n] "
read -r continue
case $continue in
    [Yy]*) ;;
    *) echo "OK, try again later when you feel ready"; exit 1 ;;
esac

echo "⚡️ Create your Swift command line project"
swift package init --type executable --name MyLambda

echo "📦 Add the AWS Lambda Swift runtime to your project"
swift package add-dependency https://github.com/swift-server/swift-aws-lambda-runtime.git --branch main
swift package add-dependency https://github.com/swift-server/swift-aws-lambda-events.git --branch main
swift package add-target-dependency AWSLambdaRuntime MyLambda --package swift-aws-lambda-runtime
swift package add-target-dependency AWSLambdaEvents MyLambda --package swift-aws-lambda-events

echo "📝 Scaffold the Lambda function code"
swift package lambda-init --allow-writing-to-package-directory

echo "📦 Compile and package the function for deployment (this might take a while)"
swift package --allow-network-connections docker lambda-build

echo "🚀 Deploy to AWS Lambda"
swift package --allow-network-connections all:443 lambda-deploy

echo ""
echo "⏰ Waiting 5 secs for the Lambda function to be ready..."
sleep 5

echo "🔗 Invoke the Lambda function"
aws lambda invoke \
    --function-name MyLambda \
    --payload "$(echo '{"name":"World","age":30}' | base64)" \
    /tmp/out.json > /dev/null && cat /tmp/out.json

echo ""
echo ""
echo "🎉 Done! Your first Lambda function in Swift is deployed on AWS Lambda."
echo ""
echo "To delete the function and clean up:"
echo "  swift package --allow-network-connections all:443 lambda-deploy --delete"
