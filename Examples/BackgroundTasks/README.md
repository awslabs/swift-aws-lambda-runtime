# Background Tasks 

This is an example for running background tasks in an AWS Lambda function.

Background tasks allow code to execute asynchronously after the main response has been returned, enabling additional processing without affecting response latency. This approach is ideal for scenarios like logging, data updates, or notifications that can be deferred. The code leverages Lambda's "Response Streaming" feature, which is effective for balancing real-time user responsiveness with the ability to perform extended tasks post-response. 

For more information about Lambda background tasks, see [this AWS blog post](https://aws.amazon.com/blogs/compute/running-code-after-returning-a-response-from-an-aws-lambda-function/).

## Code 

The sample code creates a `BackgroundProcessingHandler` struct that conforms to the `LambdaWithBackgroundProcessingHandler` protocol provided by the Swift AWS Lambda Runtime.

The `BackgroundProcessingHandler` struct defines the input and output JSON received and returned by the Handler.

The `handle(...)` method of this protocol receives incoming events as `Input` and returns the output as a `Greeting`. The `handle(...)` methods receives an `outputWriter` parameter to write the output before the function returns, giving some opportunities to run long-lasting tasks after the response has been returned to the client but before the function returns.

The `handle(...)` method uses the `outputWriter` to return the response as soon as possible. It then waits for 10 seconds to simulate a long background work.  When the 10 seconds elapsed, the function returns. The billing cycle ends when the function returns.

The `handle(...)` method is marked as `mutating` to allow handlers to be implemented with a `struct`.

Once the struct is created and the `handle(...)` method is defined, the sample code creates a `LambdaCodableAdapter` adapter to adapt the `LambdaWithBackgroundProcessingHandler` to a type accepted by the `LambdaRuntime` struct. Then, the sample code initializes the `LambdaRuntime` with the adapter just created.  Finally, the code calls `run()` to start the interaction with the AWS Lambda control plane.

## Build & Package 

To build & archive the package, type the following commands.

```bash
swift package archive --allow-network-connections docker --base-docker-image swift:amazonlinux2023
```

If there is no error, there is a ZIP file ready to deploy. 
The ZIP file is located at `.build/plugins/AWSLambdaPackager/outputs/AWSLambdaPackager/BackgroundTasks/BackgroundTasks.zip`

## Deploy with the AWS CLI

Here is how to deploy using the `aws` command line.

### Create the function

```bash
AWS_ACCOUNT_ID=012345678901
aws lambda create-function \
--function-name BackgroundTasks \
--zip-file fileb://.build/plugins/AWSLambdaPackager/outputs/AWSLambdaPackager/BackgroundTasks/BackgroundTasks.zip \
--runtime provided.al2023 \
--handler provided  \
--architectures arm64 \
--role arn:aws:iam::${AWS_ACCOUNT_ID}:role/lambda_basic_execution \
--environment "Variables={LOG_LEVEL=debug}" \
--timeout 15
```

> [!IMPORTANT] 
> The timeout value must be bigger than the time it takes for your function to complete its background tasks. Otherwise, the Lambda control plane will terminate the execution environment before your code has a chance to finish the tasks. Here, the sample function waits for 10 seconds and we set the timeout for 15 seconds.

The `--environment` arguments sets the `LOG_LEVEL` environment variable to `debug`. This will ensure the debugging statements in the handler `context.logger.debug("...")` are printed in the Lambda function logs.

The `--architectures` flag is only required when you build the binary on an Apple Silicon machine (Apple M1 or more recent). It defaults to `x64`.

Be sure to set `AWS_ACCOUNT_ID` with your actual AWS account ID (for example: 012345678901).

### Invoke your Lambda function

To invoke the Lambda function, use `aws` command line.
```bash
aws lambda invoke \
  --function-name BackgroundTasks \
  --cli-binary-format raw-in-base64-out \
  --payload '{ "message" : "Hello Background Tasks" }' \
  response.json
```

This should immediately output the following result.

```
{
    "StatusCode": 200,
    "ExecutedVersion": "$LATEST"
}
```

The response is visible in the `response.json` file.

```bash
cat response.json 
{"echoedMessage":"Hello Background Tasks"}
```

### View the function's logs 

You can observe additional messages being logged after the response is received.

To tail the log, use the AWS CLI:
```bash
aws logs tail /aws/lambda/BackgroundTasks --follow
```

This produces an output like:
```text
INIT_START Runtime Version: provided:al2.v59      Runtime Version ARN: arn:aws:lambda:us-east-1::runtime:974c4a90f22278a2ef1c3f53c5c152167318aaf123fbb07c055a4885a4e97e52
START RequestId: 4c8edd74-d776-4df9-9714-19086ab59bfd Version: $LATEST
debug LambdaRuntime : [BackgroundTasks] BackgroundProcessingHandler - message received
debug LambdaRuntime : [BackgroundTasks] BackgroundProcessingHandler - response sent. Performing background tasks.
debug LambdaRuntime : [BackgroundTasks] BackgroundProcessingHandler - Background tasks completed. Returning
END RequestId: 4c8edd74-d776-4df9-9714-19086ab59bfd
REPORT RequestId: 4c8edd74-d776-4df9-9714-19086ab59bfd    Duration: 10160.89 ms   Billed Duration: 10250 ms       Memory Size: 128 MB     Max Memory Used: 27 MB  Init Duration: 88.20 ms
```
> [!NOTE] 
> The `debug` message are sent by the code inside the `handler()` function. Note that the `Duration` and `Billed Duration` on the last line are for 10.1 and 10.2 seconds respectively.

Type CTRL-C to stop tailing the logs.

## Cleanup

When done testing, you can delete the Lambda function with this command.

```bash
aws lambda delete-function --function-name BackgroundTasks
```

## ⚠️ Security and Reliability Notice

These are example applications for demonstration purposes. When deploying such infrastructure in production environments, we strongly encourage you to follow these best practices for improved security and resiliency:

- Enable access logging on API Gateway ([documentation](https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-logging.html))
- Ensure that AWS Lambda function is configured for function-level concurrent execution limit ([concurrency documentation](https://docs.aws.amazon.com/lambda/latest/dg/lambda-concurrency.html), [configuration guide](https://docs.aws.amazon.com/lambda/latest/dg/configuration-concurrency.html))
- Check encryption settings for Lambda environment variables ([documentation](https://docs.aws.amazon.com/lambda/latest/dg/configuration-envvars-encryption.html))
- Ensure that AWS Lambda function is configured for a Dead Letter Queue (DLQ) ([documentation](https://docs.aws.amazon.com/lambda/latest/dg/invocation-async-retain-records.html#invocation-dlq))
- Ensure that AWS Lambda function is configured inside a VPC when it needs to access private resources ([documentation](https://docs.aws.amazon.com/lambda/latest/dg/configuration-vpc.html), [code example](https://github.com/awslabs/swift-aws-lambda-runtime/tree/main/Examples/ServiceLifecycle%2BPostgres))