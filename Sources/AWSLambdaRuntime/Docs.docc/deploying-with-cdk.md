# Deploy with AWS CDK

@Metadata {
    @PageKind(article)
    @PageColor(orange)
    @SupportedLanguage(swift)
    @PageImage(source: "lambda.png", alt: "AWS Lambda", purpose: icon)
}

Define and provision your Swift Lambda function with the AWS Cloud Development Kit.

## Overview

The AWS Cloud Development Kit is an open-source software development framework to define cloud infrastructure in code and provision it through AWS CloudFormation. The CDK provides high-level constructs that preconfigure AWS resources with best practices, and you can use familiar programming languages like TypeScript, Javascript, Python, Java, C#, and Go to define your infrastructure.

To use the CDK, you need to [install the CDK CLI](https://docs.aws.amazon.com/cdk/v2/guide/getting_started.html) on your machine. The CDK CLI provides a set of commands to manage your CDK projects.

Use the CDK when you want to define your infrastructure in code and manage the deployment of your Lambda function and other AWS services.

This example deploys the [APIGateway](https://github.com/awslabs/swift-aws-lambda-runtime/tree/main/Examples/APIGatewayV2) example code. It comprises a Lambda function that implements a REST API and an API Gateway to expose the function over HTTPS.

> See <doc:deploying-prerequisites> for the AWS account, credentials, and build steps this article assumes.

## Create a CDK project

To create a new CDK project, use the `cdk init` command. The command creates a new directory with the project structure and the necessary files to define your infrastructure.

```sh
# In your Swift Lambda project folder
mkdir infra && cd infra
cdk init app --language typescript
```

In this example, the code to create a Swift Lambda function with the CDK is written in TypeScript. The following code creates a new Lambda function with the `swift` runtime.

It requires the `@aws-cdk/aws-lambda` package to define the Lambda function. You can install the dependency with the following command:

```sh
npm install aws-cdk-lib constructs
```

Then, in the lib folder, create a new file named `swift-lambda-stack.ts` with the following content:

```typescript
import * as cdk from 'aws-cdk-lib';
import * as lambda from 'aws-cdk-lib/aws-lambda';

export class LambdaApiStack extends cdk.Stack {
  constructor(scope: cdk.App, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Create the Lambda function
    const lambdaFunction = new lambda.Function(this, 'SwiftLambdaFunction', {
      runtime: lambda.Runtime.PROVIDED_AL2023,
      architecture: lambda.Architecture.ARM_64,
      handler: 'bootstrap',
      code: lambda.Code.fromAsset('../.build/plugins/AWSLambdaBuilder/outputs/AWSLambdaBuilder/APIGatewayLambda/APIGatewayLambda.zip'),
      memorySize: 128,
      timeout: cdk.Duration.seconds(30),
      environment: {
        LOG_LEVEL: 'debug',
      },
    });
 }
}    
```
The code assumes you already built and packaged the APIGateway Lambda function with the `swift package lambda-build` command, as described in <doc:deploying-prerequisites>.

You can write code to add an API Gateway to invoke your Lambda function. The following code creates an HTTP API Gateway that triggers the Lambda function.

```typescript
// in the import section at the top
import * as apigateway from 'aws-cdk-lib/aws-apigatewayv2';
import { HttpLambdaIntegration } from 'aws-cdk-lib/aws-apigatewayv2-integrations';

// in the constructor, after having created the Lambda function
// ...

    // Create the API Gateway
    const httpApi = new apigateway.HttpApi(this, 'HttpApi', {
      defaultIntegration: new HttpLambdaIntegration({
        handler: lambdaFunction,
      }),
    });

    // Output the API Gateway endpoint
    new cdk.CfnOutput(this, 'APIGatewayEndpoint', {
      value: httpApi.url!,
    });

// ...    
```

## Deploy the infrastructure

To deploy the infrastructure, type the following commands.

```sh
# Change to the infra directory
cd infra

# Install the dependencies (only before the first deployment)
npm install 

# Deploy the infrastructure
cdk deploy

✨  Synthesis time: 2.88s
... redacted for brevity ...
Do you wish to deploy these changes (y/n)? y
... redacted for brevity ...
 ✅  LambdaApiStack

✨  Deployment time: 42.96s

Outputs:
LambdaApiStack.ApiUrl = https://tyqnjcawh0.execute-api.eu-central-1.amazonaws.com/
Stack ARN:
arn:aws:cloudformation:eu-central-1:012345678901:stack/LambdaApiStack/e0054390-be05-11ef-9504-065628de4b89

✨  Total time: 45.84s
```

## Invoke your Lambda function

To invoke the Lambda function, use this `curl` command line.

```bash
curl https://tyqnjcawh0.execute-api.eu-central-1.amazonaws.com
```

Be sure to replace the URL with the API Gateway endpoint returned in the previous step.

This should print a JSON similar to 

```bash 
{"version":"2.0","rawPath":"\/","isBase64Encoded":false,"rawQueryString":"","headers":{"user-agent":"curl\/8.7.1","accept":"*\/*","host":"a5q74es3k2.execute-api.us-east-1.amazonaws.com","content-length":"0","x-amzn-trace-id":"Root=1-66fb0388-691f744d4bd3c99c7436a78d","x-forwarded-port":"443","x-forwarded-for":"81.0.0.43","x-forwarded-proto":"https"},"requestContext":{"requestId":"e719cgNpoAMEcwA=","http":{"sourceIp":"81.0.0.43","path":"\/","protocol":"HTTP\/1.1","userAgent":"curl\/8.7.1","method":"GET"},"stage":"$default","apiId":"a5q74es3k2","time":"30\/Sep\/2024:20:01:12 +0000","timeEpoch":1727726472922,"domainPrefix":"a5q74es3k2","domainName":"a5q74es3k2.execute-api.us-east-1.amazonaws.com","accountId":"012345678901"}
```

If you have `jq` installed, you can use it to pretty print the output.

```bash
curl -s  https://tyqnjcawh0.execute-api.eu-central-1.amazonaws.com | jq   
{
  "version": "2.0",
  "rawPath": "/",
  "requestContext": {
    "domainPrefix": "a5q74es3k2",
    "stage": "$default",
    "timeEpoch": 1727726558220,
    "http": {
      "protocol": "HTTP/1.1",
      "method": "GET",
      "userAgent": "curl/8.7.1",
      "path": "/",
      "sourceIp": "81.0.0.43"
    },
    "apiId": "a5q74es3k2",
    "accountId": "012345678901",
    "requestId": "e72KxgsRoAMEMSA=",
    "domainName": "a5q74es3k2.execute-api.us-east-1.amazonaws.com",
    "time": "30/Sep/2024:20:02:38 +0000"
  },
  "rawQueryString": "",
  "routeKey": "$default",
  "headers": {
    "x-forwarded-for": "81.0.0.43",
    "user-agent": "curl/8.7.1",
    "host": "a5q74es3k2.execute-api.us-east-1.amazonaws.com",
    "accept": "*/*",
    "x-amzn-trace-id": "Root=1-66fb03de-07533930192eaf5f540db0cb",
    "content-length": "0",
    "x-forwarded-proto": "https",
    "x-forwarded-port": "443"
  },
  "isBase64Encoded": false
}
```

## Delete the infrastructure

When done testing, you can delete the infrastructure with this command.

```bash
cdk destroy

Are you sure you want to delete: LambdaApiStack (y/n)? y
LambdaApiStack: destroying... [1/1]
... redacted for brevity ...
 ✅  LambdaApiStack: destroyed
```
