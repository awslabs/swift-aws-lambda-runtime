# Hello World, with no traits

This is an example of a low-level AWS Lambda function that takes a `ByteBuffer` as input parameter and writes its response on the provided `LambdaResponseStreamWriter`.

This function disables all the default traits: the support for JSON Encoder and Decoder from Foundation, the support for Swift Service Lifecycle, and for the local tetsing server.

The main reasons of the existence of this example are 

1. to show how to write a low-level Lambda function that doesn't rely on JSON encodinga and decoding.
2. to show you how to disable traits when using the Lambda Runtime Library.
3. to add an integration test to our continous integration pipeline to make sure the library compiles with no traits enabled.

## Disabling all traits

Traits are functions of the AWS Lambda Runtime that you can disable at compile time to reduce the size of your binary, and therefore reduce the cold start time of your Lambda function.

The library supports three traits:

- "FoundationJSONSupport": adds the required API to encode and decode payloads with Foundation's `JSONEncoder` and `JSONDecoder`.

- "ServiceLifecycleSupport": adds support for the Swift Service Lifecycle library.

- "LocalServerSupport": adds support for testing your function locally with a built-in HTTP server.

This example disables all the traits. To disable one or several traits, modify `Package.swift`:

```swift
	dependencies: [
			.package(url: "https://github.com/awslabs/swift-aws-lambda-runtime.git", from: "2.0.0-beta", traits: [])
	],
```

## Code 

The code creates a `LambdaRuntime` struct. In its simplest form, the initializer takes a function as argument. The function is the handler that will be invoked when an event triggers the Lambda function.

The handler signature is `(event: ByteBuffer, response: LambdaResponseStreamWriter, context: LambdaContext)`.

The function takes three arguments:
- the event argument is a `ByteBuffer`. It's the parameter passed when invoking the function. You are responsible of decoding this parameter, if necessary.
- the response writer provides you with functions to write the response stream back.
- the context argument is a `Lambda Context`. It is a description of the runtime context.

The function return value will be encoded as your Lambda function response.

## Test locally 

You cannot test this function locally, because the "LocalServer" trait is disabled.

## Build & Package 

To build & archive the package, type the following commands.

```bash
swift build
swift package archive --allow-network-connections docker --base-docker-image swift:amazonlinux2023
```

If there is no error, there is a ZIP file ready to deploy. 
The ZIP file is located at `.build/plugins/AWSLambdaPackager/outputs/AWSLambdaPackager/MyLambda/MyLambda.zip`

## Deploy

Here is how to deploy using the `aws` command line.

```bash
aws lambda create-function \
--function-name MyLambda \
--zip-file fileb://.build/plugins/AWSLambdaPackager/outputs/AWSLambdaPackager/MyLambda/MyLambda.zip \
--runtime provided.al2023 \
--handler provided  \
--architectures arm64 \
--role arn:aws:iam::<YOUR_ACCOUNT_ID>:role/lambda_basic_execution
```

The `--architectures` flag is only required when you build the binary on an Apple Silicon machine (Apple M1 or more recent). It defaults to `x64`.

Be sure to replace <YOUR_ACCOUNT_ID> with your actual AWS account ID (for example: 012345678901).

## Invoke your Lambda function

To invoke the Lambda function, use this `aws` command line.

```bash
aws lambda invoke \
--function-name MyLambda \
--payload $(echo "Seb" | base64)  \
out.txt && cat out.txt && rm out.txt
```

This should output the following result. 

```
{
    "StatusCode": 200,
    "ExecutedVersion": "$LATEST"
}
"Hello World!"
```

## Undeploy

When done testing, you can delete the Lambda function with this command.

```bash
aws lambda delete-function --function-name MyLambda
```

## ⚠️ Security and Reliability Notice

These are example applications for demonstration purposes. When deploying such infrastructure in production environments, we strongly encourage you to follow these best practices for improved security and resiliency:

- Enable access logging on API Gateway ([documentation](https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-logging.html))
- Ensure that AWS Lambda function is configured for function-level concurrent execution limit ([concurrency documentation](https://docs.aws.amazon.com/lambda/latest/dg/lambda-concurrency.html), [configuration guide](https://docs.aws.amazon.com/lambda/latest/dg/configuration-concurrency.html))
- Check encryption settings for Lambda environment variables ([documentation](https://docs.aws.amazon.com/lambda/latest/dg/configuration-envvars-encryption.html))
- Ensure that AWS Lambda function is configured for a Dead Letter Queue (DLQ) ([documentation](https://docs.aws.amazon.com/lambda/latest/dg/invocation-async-retain-records.html#invocation-dlq))
- Ensure that AWS Lambda function is configured inside a VPC when it needs to access private resources ([documentation](https://docs.aws.amazon.com/lambda/latest/dg/configuration-vpc.html), [code example](https://github.com/awslabs/swift-aws-lambda-runtime/tree/main/Examples/ServiceLifecycle%2BPostgres))