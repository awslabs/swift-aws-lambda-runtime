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

# Connect with ssh 

export PATH=/home/ubuntu/swift-6.0.3-RELEASE-ubuntu24.04-aarch64/usr/bin:"${PATH}"

# clone a project 
git clone https://github.com/awslabs/swift-aws-lambda-runtime.git

# be sure Swift is install.  
# Youc an install swift with the following command: ./scripts/ubuntu-install-swift.sh

# build the project
cd swift-aws-lambda-runtime/Examples/ResourcesPackaging/ || exit 1
swift package archive --allow-network-connections docker                                      
