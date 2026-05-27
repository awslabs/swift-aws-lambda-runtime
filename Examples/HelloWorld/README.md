# Hello World 

This is a simple example of an AWS Lambda function that takes a `String` as input parameter and returns a `String` as response.

## Code 

The code creates a `LambdaRuntime` struct. In it's simplest form, the initializer takes a function as argument. The function is the handler that will be invoked when an event triggers the Lambda function.

The handler is `(event: String, context: LambdaContext)`. The function takes two arguments:
- the event argument is a `String`. It is the parameter passed when invoking the function.
- the context argument is a `Lambda Context`. It is a description of the runtime context.

The function return value will be encoded as your Lambda function response.

## Test locally 

You can test your function locally before deploying it to AWS Lambda.

To start the local function, type the following commands:

```bash
swift run
```

It will compile your code and start the local server. You know the local server is ready to accept connections when you see this message.

```txt
Building for debugging...
[1/1] Write swift-version--644A47CB88185983.txt
Build of product 'MyLambda' complete! (0.31s)
2025-01-29T12:44:48+0100 info LocalServer : host="127.0.0.1" port=7000 [AWSLambdaRuntime] Server started and listening
```

Then, from another Terminal, send your payload with `curl`. Note that the payload must be a valid JSON string. In the case of this function that accepts a simple String, it means the String must be wrapped in between double quotes.

```bash
curl -d '"seb"' http://127.0.0.1:7000/invoke    
"Hello seb"
```

> [!IMPORTANT]
> The local server is only available in `DEBUG` mode. It will not start with `swift -c release run`.

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
--payload $(echo \"Seb\" | base64)  \
out.txt && cat out.txt && rm out.txt
```

Note that the payload is expected to be a valid JSON string, hence the surroundings quotes (`"`).

This should output the following result. 

```
{
    "StatusCode": 200,
    "ExecutedVersion": "$LATEST"
}
"Hello Seb"
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