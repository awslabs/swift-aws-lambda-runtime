# Deploy Swift Lambda functions with .zip file archives or OCI container images

This page describes how to compile your Swift function, and then deploy the compiled binary to AWS Lambda. It shows how to deploy using the Swift AWS Lambda Runtime plugin, the AWS Command Line Interface, and the AWS Serverless Application Model CLI.

## Building Swift functions on macOS, Windows, or Linux

The following steps demonstrate how to create the project for your first Lambda function with Swift and compile it using the Swift AWS Lambda Runtime's built-in SwiftPM plugin, which simplifies building and deploying Swift Lambda functions.

### Prerequisites

- Swift 6.3 toolchain or later (macOS 15 Sequoia or later on macOS)
- Docker, Apple container, or the Swift Static Linux SDK installed — to cross-compile for Amazon Linux
- AWS CLI configured with `aws configure`

### Steps

1. **Create a new Swift Lambda function project:**

   ```bash
   mkdir MyFunction && cd MyFunction
   swift package init --type executable
   swift package add-dependency https://github.com/awslabs/swift-aws-lambda-runtime.git --from 3.0.0
   swift package add-target-dependency AWSLambdaRuntime MyFunction --package swift-aws-lambda-runtime
   ```

2. **Scaffold a minimal function using the built-in plugin:**

   ```bash
   swift package lambda-init --allow-writing-to-package-directory
   ```

3. **Test your function locally.** `swift run` starts a local server on port 7000:

   ```bash
   swift run &
   curl --header "Content-Type: application/json" \
        --data '{"name":"World","age":30}' \
        http://127.0.0.1:7000/invoke
   ```

4. **Build for Amazon Linux using the plugin:**

   AWS Lambda runs on Amazon Linux. You must cross-compile your code for that platform. The `lambda-build` plugin handles this automatically using one of three cross-compilation methods:

   - **Docker** (default) — uses a Docker container with the Swift toolchain for Amazon Linux 2023.
   - **Apple container** — uses Apple's lightweight container runtime (available on macOS 15+) instead of Docker.
   - **Swift Static Linux SDK** — uses a pre-installed Static Linux SDK (musl-based). This method needs no Docker or container runtime. Install it with `swift sdk install <url>`.

   Select the method with the `--cross-compile` flag (`docker`, `container`, or `swift-static-sdk`). The default is `docker`.

   ```bash
   swift package --allow-network-connections docker lambda-build
   ```

   By default, the plugin compiles for the host machine's architecture (arm64 on Apple Silicon Macs, x86_64 on Intel Macs). To target a different architecture, use the `--architecture` flag:

   ```bash
   # Cross-compile for x86_64 from an Apple Silicon Mac
   swift package --allow-network-connections docker lambda-build --architecture x64
   ```

   The architecture is recorded in the build manifest. When you deploy with `lambda-deploy`, the function is automatically configured for the correct architecture.

### Building as an OCI container image

Instead of a `.zip` archive, the plugin can produce an OCI container image ready to be pushed to Amazon Elastic Container Registry (ECR). This is useful for large deployment packages or when your function requires additional system libraries. Use the `--archive-format oci` flag:

```bash
swift package --allow-network-connections docker lambda-build --archive-format oci
```

You can customize the base image with `--base-oci-image` (default: `public.ecr.aws/amazonlinux/amazonlinux:2023-minimal`). The base image must be glibc-compatible Amazon Linux 2023.

When you deploy with `lambda-deploy`, the plugin detects the OCI format and handles pushing the image to ECR and configuring the Lambda function to use it.

## Deploying the Swift function binary with the runtime plugin

Use the deploy command to deploy the compiled binary to Lambda. This command creates an execution role and then creates the Lambda function:

```bash
swift package --allow-network-connections all:443 lambda-deploy
```

The plugin creates the IAM role, uploads the code, and creates the Lambda function automatically. When the deployment succeeds, it reports the function ARN and a ready-to-use `aws lambda invoke` command. To specify an existing execution role, use the `--role` flag.

## Deploying your Swift function binary with the AWS CLI

You can also deploy your binary with the AWS CLI.

1. **Build the .zip deployment package.** After building with the `lambda-build` command, the plugin outputs a `.zip` archive ready for deployment.

   ```bash
   swift package --allow-network-connections docker lambda-build
   ```

   The resulting archive is located at `.build/plugins/AWSLambdaBuilder/outputs/AWSLambdaBuilder/MyFunction/MyFunction.zip`.

2. **Deploy the .zip package to Lambda** by running the `create-function` command.

   - For `--runtime`, specify `provided.al2023`. This is an OS-only runtime. OS-only runtimes are used to deploy compiled binaries and custom runtimes to Lambda.
   - For `--role`, specify the ARN of the execution role.

   ```bash
   aws lambda create-function \
       --function-name my-function \
       --runtime provided.al2023 \
       --role arn:aws:iam::111122223333:role/lambda-role \
       --handler swift.bootstrap \
       --zip-file fileb://.build/plugins/AWSLambdaBuilder/outputs/AWSLambdaBuilder/MyFunction/MyFunction.zip
   ```

   If you built for a specific architecture (e.g. arm64 from an Intel Mac, or x64 from an Apple Silicon Mac), add the matching `--architectures` flag:

   ```bash
   aws lambda create-function \
       --function-name my-function \
       --runtime provided.al2023 \
       --role arn:aws:iam::111122223333:role/lambda-role \
       --handler swift.bootstrap \
       --architectures arm64 \
       --zip-file fileb://.build/plugins/AWSLambdaBuilder/outputs/AWSLambdaBuilder/MyFunction/MyFunction.zip
   ```

## Deploying your Swift function binary with the AWS SAM CLI

You can also deploy your binary with the AWS SAM CLI.

1. **Create an AWS SAM template** with the resource and property definition. For `Runtime`, specify `provided.al2023`. This is an OS-only runtime. OS-only runtimes are used to deploy compiled binaries and custom runtimes to Lambda.

   For more information about deploying Lambda functions using AWS SAM, see [AWS::Serverless::Function](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/sam-resource-function.html) in the *AWS Serverless Application Model Developer Guide*.

   **Example — SAM resource and property definition for a Swift binary**

   ```yaml
   AWSTemplateFormatVersion: '2010-09-09'
   Transform: AWS::Serverless-2016-10-31
   Description: SAM template for Swift Lambda functions
   Resources:
     SwiftFunction:
       Type: AWS::Serverless::Function
       Properties:
         CodeUri: .build/plugins/AWSLambdaBuilder/outputs/AWSLambdaBuilder/MyFunction/MyFunction.zip
         Handler: swift.bootstrap
         Runtime: provided.al2023
         MemorySize: 128
         Architectures:
           - arm64
   Outputs:
     SwiftFunction:
       Description: "Lambda Function ARN"
       Value: !GetAtt SwiftFunction.Arn
   ```

2. **Build the function:**

   ```bash
   swift package --allow-network-connections docker lambda-build
   ```

3. **Deploy the function:**

   ```bash
   sam deploy --guided
   ```

## Invoking your Swift function locally

You can test your function locally without deploying. The Swift AWS Lambda Runtime starts a local HTTP server on port 7000 when you run it outside the Lambda execution environment:

```bash
swift run &
curl --header "Content-Type: application/json" \
     --data '{"name":"World","age":30}' \
     http://127.0.0.1:7000/invoke
```

You can also configure the local server address with environment variables:

- `LOCAL_LAMBDA_HOST` — bind a different TCP address
- `LOCAL_LAMBDA_PORT` — bind a different TCP port
- `LOCAL_LAMBDA_INVOCATION_ENDPOINT` — use a different endpoint path

## Deleting your Swift function

When you're done, clean up the function and its IAM role:

```bash
swift package --allow-network-connections all:443 lambda-deploy --delete
```

## Invoking your Swift function with the AWS CLI

You can use the AWS CLI to invoke the deployed function:

```bash
aws lambda invoke \
    --function-name my-function \
    --cli-binary-format raw-in-base64-out \
    --payload '{"name":"World","age":30}' \
    /dev/stdout
```

The `cli-binary-format` option is required if you're using AWS CLI version 2. To make this the default setting, run `aws configure set cli-binary-format raw-in-base64-out`. For more information, see [AWS CLI supported global command line options](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-options.html) in the *AWS Command Line Interface User Guide for Version 2*.
