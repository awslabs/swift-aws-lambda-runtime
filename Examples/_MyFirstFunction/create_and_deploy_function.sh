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

check_prerequisites() {
    # check if docker is installed
    which docker > /dev/null || (echo "Docker is not installed.  Please install Docker and try again." && exit 1)

    # check if aws cli is installed
    which aws > /dev/null || (echo "AWS CLI is not installed.  Please install AWS CLI and try again." && exit 1)

    # check if user has an access key and secret access key
    echo "This script creates and deploys a Lambda function on your AWS Account.

    You must have an AWS account and know an AWS access key, secret access key, and an optional session token.
    These values are read from '~/.aws/credentials'.
    "

    printf "Are you ready to create your first Lambda function in Swift? [y/n] "
    read -r continue
    case $continue in
        [Yy]*) ;;
        *) echo "OK, try again later when you feel ready"; exit 1 ;;
    esac
}

create_lambda_execution_role() {
    role_name=$1

    # Allow the Lambda service to assume the IAM role
    cat <<EOF > trust-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "lambda.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF

    # Create the IAM role
    echo "🔐 Create the IAM role for the Lambda function"
    aws iam create-role \
    --role-name "${role_name}" \
    --assume-role-policy-document file://trust-policy.json > /dev/null 2>&1

    # Attach basic permissions to the role
    # The AWSLambdaBasicExecutionRole policy grants permissions to write logs to CloudWatch Logs
    echo "🔒 Attach basic permissions to the role"
    aws iam attach-role-policy \
    --role-name "${role_name}" \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole > /dev/null 2>&1

    echo "⏰ Waiting 10 secs for IAM role to propagate..."
    sleep 10
}

create_swift_project() {
    echo "⚡️ Create your Swift Lambda project"
    swift package init --type executable --name MyLambda > /dev/null

    echo "📦 Add the AWS Lambda Swift runtime to your project"
    # The following commands are commented out until the `lambad-init` plugin will be release
    # swift package add-dependency https://github.com/awslabs/swift-aws-lambda-runtime.git --from 2.0.0
    # swift package add-dependency https://github.com/awslabs/swift-aws-lambda-events.git --from 1.0.0
    # swift package add-target-dependency AWSLambdaRuntime MyLambda --package swift-aws-lambda-runtime
    # swift package add-target-dependency AWSLambdaEvents MyLambda --package swift-aws-lambda-events
    cat <<EOF > Package.swift
// swift-tools-version:6.2

import PackageDescription

let package = Package(
    name: "swift-aws-lambda-runtime-example",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "MyLambda", targets: ["MyLambda"])
    ],
    dependencies: [
        .package(url: "https://github.com/awslabs/swift-aws-lambda-runtime.git", from: "2.0.0")
    ],
    targets: [
        .executableTarget(
            name: "MyLambda",
            dependencies: [
                .product(name: "AWSLambdaRuntime", package: "swift-aws-lambda-runtime")
            ],
            path: "."
        )
    ]
)
EOF

    echo "📝 Write the Swift code"
    # The following command is commented out until the `lambad-init` plugin will be release
    # swift package lambda-init --allow-writing-to-package-directory 
    cat <<EOF > Sources/main.swift
import AWSLambdaRuntime

let runtime = LambdaRuntime {
    (event: String, context: LambdaContext) in
    "Hello \(event)"
}

try await runtime.run()
EOF

    echo "📦 Compile and package the function for deployment (this might take a while)"
    swift package archive --allow-network-connections docker > /dev/null 2>&1
}

deploy_lambda_function() {
    echo "🚀 Deploy to AWS Lambda"
    
    # retrieve your AWS Account ID 
    echo "🔑 Retrieve your AWS Account ID"
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    export AWS_ACCOUNT_ID

    # Check if the role already exists
    echo "🔍 Check if a Lambda execution IAM role already exists"
    aws iam get-role --role-name lambda_basic_execution > /dev/null 2>&1 || create_lambda_execution_role lambda_basic_execution

    # Create the Lambda function
    echo "🚀 Create the Lambda function"
    aws lambda create-function \
    --function-name MyLambda \
    --zip-file fileb://.build/plugins/AWSLambdaPackager/outputs/AWSLambdaPackager/MyLambda/MyLambda.zip \
    --runtime provided.al2 \
    --handler provided  \
    --architectures "$(uname -m)" \
    --role arn:aws:iam::"${AWS_ACCOUNT_ID}":role/lambda_basic_execution > /dev/null 2>&1

    echo "⏰ Waiting 10 secs for the Lambda function to be ready..."
    sleep 10
}

invoke_lambda_function() {
    # Invoke the Lambda function
    echo "🔗 Invoke the Lambda function"
    aws lambda invoke \
    --function-name MyLambda \
    --cli-binary-format raw-in-base64-out \
    --payload '"Lambda Swift"' \
    output.txt > /dev/null 2>&1

    echo "👀 Your Lambda function returned:"
    cat output.txt && rm output.txt
}

main() {
    #
    # Check prerequisites
    #
    check_prerequisites

    #
    # Create the Swift project
    #
    create_swift_project

    #
    # Now the function is ready to be deployed to AWS Lambda
    #
    deploy_lambda_function

    #
    # Invoke the Lambda function
    #
    invoke_lambda_function

    echo ""
    echo "🎉 Done! Your first Lambda function in Swift is now deployed on AWS Lambda. 🚀"    
}

main "$@"