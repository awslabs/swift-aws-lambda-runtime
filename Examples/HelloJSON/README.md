# Hello JSON 

This is a simple example of an AWS Lambda function that takes a JSON structure as an input parameter and returns a JSON structure as a response.

The runtime takes care of decoding the input and encoding the output.

## Code 

The code defines `HelloRequest` and `HelloResponse` data structures to represent the input and output payloads. These structures are typically shared with a client project, such as an iOS application.

The code creates a `LambdaRuntime` struct. In it's simplest form, the initializer takes a function as an argument. The function is the handler that will be invoked when an event triggers the Lambda function.

The handler is `(event: HelloRequest, context: LambdaContext)`. The function takes two arguments:
- the event argument is a `HelloRequest`. It is the parameter passed when invoking the function.
- the context argument is a `Lambda Context`. It is a description of the runtime context.

The function return value will be encoded to a `HelloResponse` as your Lambda function response.

## Build & Package 

To build & archive the package, type the following commands.

```bash
swift package --allow-network-connections docker lambda-build
```

If there is no error, there is a ZIP file ready to deploy. 
The ZIP file is located at `.build/plugins/AWSLambdaBuilder/outputs/AWSLambdaBuilder/HelloJSON/HelloJSON.zip`

## Deploy

Here is how to deploy using the `lambda-deploy` plugin.

```bash
swift package --allow-network-connections all:443 lambda-deploy
```

This creates the Lambda function, provisions the necessary IAM role, and uploads the deployment package.

## Invoke your Lambda function

To invoke the Lambda function, use this `aws` command line.

```bash
aws lambda invoke \
--function-name HelloJSON \
--payload $(echo '{ "name" : "Seb", "age" : 50 }' | base64)  \
out.txt && cat out.txt && rm out.txt
```

Note that the payload is expected to be a valid JSON string.

This should output the following result. 

```
{
    "StatusCode": 200,
    "ExecutedVersion": "$LATEST"
}
{"greetings":"Hello Seb. You look younger than your age."}
```

## Undeploy

When done testing, you can delete the Lambda function with this command.

```bash
swift package --allow-network-connections all:443 lambda-deploy --delete
```

## ⚠️ Security and Reliability Notice

These are example applications for demonstration purposes. When deploying such infrastructure in production environments, we strongly encourage you to follow these best practices for improved security and resiliency:

- Enable access logging on API Gateway ([documentation](https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-logging.html))
- Ensure that AWS Lambda function is configured for function-level concurrent execution limit ([concurrency documentation](https://docs.aws.amazon.com/lambda/latest/dg/lambda-concurrency.html), [configuration guide](https://docs.aws.amazon.com/lambda/latest/dg/configuration-concurrency.html))
- Check encryption settings for Lambda environment variables ([documentation](https://docs.aws.amazon.com/lambda/latest/dg/configuration-envvars-encryption.html))
- Ensure that AWS Lambda function is configured for a Dead Letter Queue (DLQ) ([documentation](https://docs.aws.amazon.com/lambda/latest/dg/invocation-async-retain-records.html#invocation-dlq))
- Ensure that AWS Lambda function is configured inside a VPC when it needs to access private resources ([documentation](https://docs.aws.amazon.com/lambda/latest/dg/configuration-vpc.html), [code example](https://github.com/awslabs/swift-aws-lambda-runtime/tree/main/Examples/ServiceLifecycle%2BPostgres))