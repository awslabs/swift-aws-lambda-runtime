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
swift package archive --allow-network-connections docker
```

If there is no error, there is a ZIP file ready to deploy. 
The ZIP file is located at `.build/plugins/AWSLambdaPackager/outputs/AWSLambdaPackager/HelloJSON/HelloJSON.zip`

## Deploy

Here is how to deploy using the `aws` command line.

```bash
# Replace with your AWS Account ID
AWS_ACCOUNT_ID=012345678901

aws lambda create-function \
--function-name HelloJSON \
--zip-file fileb://.build/plugins/AWSLambdaPackager/outputs/AWSLambdaPackager/HelloJSON/HelloJSON.zip \
--runtime provided.al2 \
--handler provided  \
--architectures arm64 \
--role arn:aws:iam::${AWS_ACCOUNT_ID}:role/lambda_basic_execution
```

The `--architectures` flag is only required when you build the binary on an Apple Silicon machine (Apple M1 or more recent). It defaults to `x64`.

Be sure to define the `AWS_ACCOUNT_ID` environment variable with your actual AWS account ID (for example: 012345678901).

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
aws lambda delete-function --function-name HelloJSON
```