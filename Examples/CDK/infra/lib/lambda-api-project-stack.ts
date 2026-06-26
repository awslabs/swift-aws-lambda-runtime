//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftAWSLambdaRuntime open source project
//
// Copyright SwiftAWSLambdaRuntime project authors
// Copyright (c) Amazon.com, Inc. or its affiliates.
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftAWSLambdaRuntime project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//
 
import * as cdk from 'aws-cdk-lib';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as apigateway from 'aws-cdk-lib/aws-apigatewayv2';
import { HttpLambdaIntegration } from 'aws-cdk-lib/aws-apigatewayv2-integrations';

export class LambdaApiStack extends cdk.Stack {
  constructor(scope: cdk.App, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Create the Lambda function
    const lambdaFunction = new lambda.Function(this, 'SwiftLambdaFunction', {
      runtime: lambda.Runtime.PROVIDED_AL2,
      architecture: lambda.Architecture.ARM_64,
      handler: 'bootstrap',
      code: lambda.Code.fromAsset('../.build/plugins/AWSLambdaBuilder/outputs/AWSLambdaBuilder/APIGatewayLambda/APIGatewayLambda.zip'),
      memorySize: 128,
      timeout: cdk.Duration.seconds(30),
      environment: {
        LOG_LEVEL: 'debug',
      },
    });

    // Create the integration
    const integration = new HttpLambdaIntegration(
      'LambdaIntegration',
      lambdaFunction
    );

    // Create HTTP API with the integration
    const httpApi = new apigateway.HttpApi(this, 'HttpApi', {
      defaultIntegration: integration,
    });

    // Output the API URL
    new cdk.CfnOutput(this, 'ApiUrl', {
      value: httpApi.url ?? 'Something went wrong',
    });
  }
}

