# Deploy with the lambda-deploy plugin

@Metadata {
    @PageKind(article)
    @PageColor(orange)
    @SupportedLanguage(swift)
    @PageImage(source: "lambda.png", alt: "AWS Lambda", purpose: icon)
}

Deploy your Swift Lambda function from the command line with the bundled `lambda-deploy` plugin.

## Overview

The `lambda-deploy` plugin provides the simplest way to deploy your Lambda function from the command line. It handles IAM role creation, code upload, and function creation or update automatically.

In this example, we're building the HelloWorld example from the [Examples](https://github.com/awslabs/swift-aws-lambda-runtime/tree/main/Examples) directory.

> See <doc:deploying-prerequisites> for the AWS account, credentials, and build steps this article assumes.

## Prerequisites

The only prerequisite is to have the [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) installed and configured. Run `aws configure` to create the `~/.aws/config` and `~/.aws/credentials` files that the plugin reads.

```sh
aws configure
```

## How credentials are resolved

`lambda-deploy` does not implement its own credential handling. It leverages your existing AWS CLI configuration to locate credentials, using the same resolution chain as [Soto Core](https://github.com/soto-project/soto-core). Soto Core is the foundation of [Soto](https://soto.codes), the community-maintained AWS SDK for Swift; it provides the request signing and credential resolution that the plugin reuses. This means any credential source you already use with the AWS CLI works without extra configuration:

- Long-term credentials (access key and secret access key) in `~/.aws/credentials` (**strongly discouraged**)
- AWS IAM Identity Center (SSO) and `aws sso login` sessions (**best practice for humans deploying from the Terminal**)
- Roles assumed through your AWS config profiles
- Amazon EC2 instance metadata (IMDS)
- Container credentials on Amazon ECS and Amazon EKS (**best when running in a CI**)

On EC2, ECS, or EKS, credentials are typically provided automatically by the instance or task role, so running `aws configure` is not required in those environments.

If you maintain several AWS CLI profiles, select one with the `--profile` option, exactly as you would with the AWS CLI. The plugin reads the credentials and region from that profile.

```sh
swift package --allow-network-connections all:443 lambda-deploy --profile my-profile
```

## Create or update the function

The `lambda-deploy` plugin automatically detects whether the function exists. If the function does not exist, it creates a new one (including the IAM role). If the function already exists, it updates the code.

The command assumes you've already built the ZIP file or OCI image with `swift package lambda-build`, as described in <doc:deploying-prerequisites>.

```sh
swift package --allow-network-connections all:443 lambda-deploy
```

When the deployment succeeds, the plugin reports the function ARN, region, and a ready-to-use invocation command.

## Invoke the function

Use the command displayed by the plugin after deployment:

```sh
aws lambda invoke \
  --function-name MyLambda \
  --payload $(echo '{"name":"World","age":30}' | base64) \
  /dev/stdout
```

## Deploy with a Function URL

To expose the function as an HTTPS endpoint, add the `--with-url` option:

```sh
swift package --allow-network-connections all:443 lambda-deploy --with-url
```

> **Security:** The Function URL uses IAM authentication (`AWS_IAM`) and the resource policy restricts access to authenticated IAM principals in your AWS account only. Unauthenticated requests and requests from other accounts are rejected. Callers must sign requests with AWS Signature Version 4. See [Lambda Function URL security and auth model](https://docs.aws.amazon.com/lambda/latest/dg/urls-auth.html) for details.

> **Note:** Function URLs deliver a `FunctionURLRequest` and expect a `FunctionURLResponse`. Your Lambda function code must use these types (from `AWSLambdaEvents`) instead of plain JSON structs. Use `swift package lambda-init --with-url` to scaffold a function with the correct request/response pattern, or see the [Streaming+FunctionUrl](https://github.com/awslabs/swift-aws-lambda-runtime/tree/main/Examples/Streaming+FunctionUrl) example.

The plugin reports the Function URL and a ready-to-use `curl` command. Invoke it with:

```sh
(eval $(aws configure export-credentials --format env) && \
  curl --aws-sigv4 "aws:amz:us-east-1:lambda" \
       --user "$AWS_ACCESS_KEY_ID:$AWS_SECRET_ACCESS_KEY" \
       -H "x-amz-security-token: $AWS_SESSION_TOKEN" \
       "https://<your-function-url>.lambda-url.<region>.on.aws/")
```

> The `eval $(aws configure export-credentials --format env)` command exports your AWS credentials as environment variables from whatever credential source you have configured (SSO, config file, assumed role, etc.).

## Delete the function

Remove the Lambda function and its associated IAM role:

```sh
swift package --allow-network-connections all:443 lambda-deploy --delete
```
