# Deploying your Swift Lambda functions

@Metadata {
    @PageKind(article)
    @PageColor(orange)
    @SupportedLanguage(swift)
    @PageImage(source: "lambda.png", alt: "AWS Lambda", purpose: icon)
}

Learn how to deploy your Swift Lambda functions to AWS.

## Overview

There are multiple ways to deploy your Swift code to AWS Lambda. The simplest way is to use the `lambda-deploy` plugin that handles IAM role creation, code upload, and function management automatically. For more complex deployments, we recommend using Infrastructure as Code (IaC) tools like the [AWS Serverless Application Model (SAM)](https://aws.amazon.com/serverless/sam/) or [AWS Cloud Development Kit (CDK)](https://aws.amazon.com/cdk/). These tools allow you to define your infrastructure and deployment process as code, which can be version-controlled and automated.

Whichever method you choose, start with <doc:deploying-prerequisites>. It covers the AWS account, credentials, region, and execution role that every deployment needs, and how to build and package your function.

Then pick the method that fits your needs:

- <doc:deploying-with-the-plugin> is the fastest path from the command line.
- <doc:deploying-with-the-console> uploads and tests your function manually, useful the first time.
- <doc:deploying-with-sam> and <doc:deploying-with-cdk> let you define your function and its supporting AWS resources as code.

### Third-party tools

Alternatively, you might consider using popular third-party tools like [Serverless Framework](https://www.serverless.com/), [Terraform](https://www.terraform.io/), or [Pulumi](https://www.pulumi.com/) to deploy Lambda functions and create and manage AWS infrastructure.

We welcome contributions to this section. If you have experience deploying Swift Lambda functions with these tools, please share your knowledge with the community.

### ⚠️ Security and Reliability Notice

These are example applications for demonstration purposes. When deploying such infrastructure in production environments, we strongly encourage you to follow these best practices for improved security and resiliency:

- Enable access logging on API Gateway ([documentation](https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-logging.html))
- Ensure that AWS Lambda function is configured for function-level concurrent execution limit ([concurrency documentation](https://docs.aws.amazon.com/lambda/latest/dg/lambda-concurrency.html), [configuration guide](https://docs.aws.amazon.com/lambda/latest/dg/configuration-concurrency.html))
- Check encryption settings for Lambda environment variables ([documentation](https://docs.aws.amazon.com/lambda/latest/dg/configuration-envvars-encryption.html))
- Ensure that AWS Lambda function is configured for a Dead Letter Queue (DLQ) ([documentation](https://docs.aws.amazon.com/lambda/latest/dg/invocation-async-retain-records.html#invocation-dlq))
- Ensure that AWS Lambda function is configured inside a VPC when it needs to access private resources ([documentation](https://docs.aws.amazon.com/lambda/latest/dg/configuration-vpc.html), [code example](https://github.com/awslabs/swift-aws-lambda-runtime/tree/main/Examples/ServiceLifecycle%2BPostgres))

## Topics

### Before you deploy

- <doc:deploying-prerequisites>

### Deployment methods

- <doc:deploying-with-the-plugin>
- <doc:deploying-with-the-console>
- <doc:deploying-with-sam>
- <doc:deploying-with-cdk>
