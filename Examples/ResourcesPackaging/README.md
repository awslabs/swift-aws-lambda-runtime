# Resources Packaging 

This is an example of an AWS Lambda function that reads a bundled resource file and returns its content as a response.

This example demonstrates how to include static resources (such as text files, configuration files, or templates) in your Lambda function package using Swift Package Manager's resource bundling feature.

## Code 

The code creates a `LambdaRuntime` struct with a handler that reads a bundled text file and returns its content.

The handler is `(event: String, context: LambdaContext)`. The function takes two arguments:
- the event argument is a `String`. It is the parameter passed when invoking the function.
- the context argument is a `Lambda Context`. It is a description of the runtime context.

The handler uses `Bundle.module.url(forResource:withExtension:)` to locate the `hello.txt` file that was bundled with the executable at build time. It then reads the file content and returns it as the function response.

The `Package.swift` file declares the resource using the `.process("hello.txt")` directive, which tells Swift Package Manager to include the file in the module's resource bundle.

## Test locally 

You can test your function locally before deploying it to AWS Lambda.

To start the local function, type the following commands:

```bash
swift run
```

It will compile your code and start the local server. You know the local server is ready to accept connections when you see this message.

```txt
Building for debugging...
Build of product 'MyLambda' complete! (0.31s)
2025-01-29T12:44:48+0100 info LocalServer : host="127.0.0.1" port=7000 [AWSLambdaRuntime] Server started and listening
```

Then, from another Terminal, send your payload with `curl`.

```bash
curl -d '"hello"' http://127.0.0.1:7000/invoke    
"Hello World\n"
```

> [!IMPORTANT]
> The local server is only available in `DEBUG` mode. It will not start with `swift -c release run`.

## Build & Package 

To build & archive the package, type the following commands.

```bash
swift package archive --allow-network-connections docker
```

If there is no error, there is a ZIP file ready to deploy. 
The ZIP file is located at `.build/plugins/AWSLambdaPackager/outputs/AWSLambdaPackager/MyLambda/MyLambda.zip`

## Deploy

Here is how to deploy using the `aws` command line.

```bash
aws lambda create-function \
--function-name MyLambda \
--zip-file fileb://.build/plugins/AWSLambdaPackager/outputs/AWSLambdaPackager/MyLambda/MyLambda.zip \
--runtime provided.al2 \
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
--payload $(echo \"hello\" | base64)  \
out.txt && cat out.txt && rm out.txt
```

This should output the following result. 

```
{
    "StatusCode": 200,
    "ExecutedVersion": "$LATEST"
}
"Hello World\n"
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
