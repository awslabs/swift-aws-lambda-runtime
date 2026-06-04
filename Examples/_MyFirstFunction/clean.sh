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

echo "This script deletes the Lambda function and IAM role, then removes local project files."
read -r -p "Are you sure you want to delete everything? [y/n] " continue
if [[ ! $continue =~ ^[Yy]$ ]]; then
  echo "OK, try again later when you feel ready"
  exit 1
fi

echo "🗑️  Deleting the Lambda function and IAM role"
swift package --allow-network-connections all:443 lambda-deploy --delete || true

echo "🧹 Deleting local project files"
rm -rf .build
rm -rf ./Sources
rm -f Package.swift Package.resolved

echo "🎉 Done! Your project is cleaned up and ready for a fresh start."
