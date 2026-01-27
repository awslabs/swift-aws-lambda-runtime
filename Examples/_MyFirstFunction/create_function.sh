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

# check if docker is installed
if ! which docker > /dev/null; then
    echo "Docker is not installed.  Please install Docker and try again."
    exit 1
fi

# check if user has an access key and secret access key
echo "This script creates and deploys a Lambda function on your AWS Account.

You must have an AWS account and know an AWS access key, secret access key, and an optional session token.  These values are read from '~/.aws/credentials' or asked interactively.
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

echo "📝 Write the Swift code"
swift package lambda-init --allow-writing-to-package-directory 

echo "📦 Compile and package the function for deployment"
swift package archive --allow-network-connections docker

echo "🚀 Deploy to AWS Lambda"


