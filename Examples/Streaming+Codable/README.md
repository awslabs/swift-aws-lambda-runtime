# Streaming Codable Lambda function

This example demonstrates how to use a `StreamingLambdaHandlerWithEvent` protocol to create Lambda functions, exposed through a FunctionUrl, that:

1. **Receive JSON input**: Automatically decode JSON events into Swift structs
2. **Stream responses**: Send data incrementally as it becomes available
3. **Execute background work**: Perform additional processing after the response is sent

## When to Use This Approach

**⚠️ Important Limitations:**

1. **Function URL Only**: This streaming codable approach only works with Lambda functions exposed through [Lambda Function URLs](https://docs.aws.amazon.com/lambda/latest/dg/urls-configuration.html)
2. **Limited Request Access**: This approach hides the details of the `FunctionURLRequest` (like HTTP headers, query parameters, etc.) from developers

**Decision Rule:**

- **Use this streaming codable approach when:**
  - Your function is exposed through a Lambda Function URL
  - You have a JSON payload that you want automatically decoded
  - You don't need to inspect HTTP headers, query parameters, or other request details
  - You prioritize convenience over flexibility

- **Use the ByteBuffer `StreamingLambdaHandler` approach when:**
  - You need full control over the `FunctionURLRequest` details
  - You're invoking the Lambda through other means (API Gateway, direct invocation, etc.)
  - You need access to HTTP headers, query parameters, or request metadata
  - You require maximum flexibility (requires writing more code)

This example balances convenience and flexibility. The streaming codable interface combines the benefits of:
- Type-safe JSON input decoding (like regular `LambdaHandler`)
- Response streaming capabilities (like `StreamingLambdaHandler`)
- Background work execution after response completion

Streaming responses incurs a cost. For more information, see [AWS Lambda Pricing](https://aws.amazon.com/lambda/pricing/).

You can stream responses through [Lambda function URLs](https://docs.aws.amazon.com/lambda/latest/dg/urls-configuration.html), the AWS SDK, or using the Lambda [InvokeWithResponseStream](https://docs.aws.amazon.com/lambda/latest/dg/API_InvokeWithResponseStream.html) API.

## Code

The sample code creates a `StreamingFromEventHandler` struct that conforms to the `StreamingLambdaHandlerWithEvent` protocol provided by the Swift AWS Lambda Runtime.

The `handle(...)` method of this protocol receives incoming events as a decoded Swift struct (`StreamingRequest`) and returns the output through a `LambdaResponseStreamWriter`.

The Lambda function expects a JSON payload with the following structure:

```json
{
  "count": 5,
  "message": "Hello from streaming Lambda!",
  "delayMs": 1000
}
```

Where:
- `count`: Number of messages to stream (1-100)
- `message`: The message content to repeat
- `delayMs`: Optional delay between messages in milliseconds (defaults to 500ms)

The response is streamed through the `LambdaResponseStreamWriter`, which is passed as an argument in the `handle` function. The code calls the `write(_:)` function of the `LambdaResponseStreamWriter` with partial data written repeatedly before finally closing the response stream by calling `finish()`. Developers can also choose to return the entire output and not stream the response by calling `writeAndFinish(_:)`.

An error is thrown if `finish()` is called multiple times or if it is called after having called `writeAndFinish(_:)`.

The `handle(...)` method is marked as `mutating` to allow handlers to be implemented with a `struct`.

Once the struct is created and the `handle(...)` method is defined, the sample code creates a `LambdaRuntime` struct and initializes it with the handler just created. Then, the code calls `run()` to start the interaction with the AWS Lambda control plane.

Key features demonstrated:
- **JSON Input Decoding**: The function automatically parses the JSON input into a `StreamingRequest` struct
- **Input Validation**: Validates the count parameter and returns an error message if invalid
- **Progressive Streaming**: Sends messages one by one with configurable delays
- **Timestamped Output**: Each message includes an ISO8601 timestamp
- **Background Processing**: Performs cleanup and logging after the response is complete
- **Error Handling**: Gracefully handles invalid input with descriptive error messages

## Build & Package

To build & archive the package, type the following commands.

```bash
swift package archive --allow-network-connections docker
```

If there is no error, there is a ZIP file ready to deploy.
The ZIP file is located at `.build/plugins/AWSLambdaPackager/outputs/AWSLambdaPackager/StreamingFromEvent/StreamingFromEvent.zip`

## Test locally

You can test the function locally before deploying:

```bash
swift run 

# In another terminal, test with curl:
curl -v \
  --header "Content-Type: application/json" \
  --data '{"count": 3, "message": "Hello World!", "delayMs": 1000}' \
  http://127.0.0.1:7000/invoke
```

Or simulate a call from a Lambda Function URL (where the body is encapsulated in a Lambda Function URL request):

```bash 
curl -v \
  --header "Content-Type: application/json" \
  --data @events/sample-request.json \
  http://127.0.0.1:7000/invoke
  ```

## Deploy with the AWS CLI

Here is how to deploy using the `aws` command line.

### Step 1: Create the function

```bash
# Replace with your AWS Account ID
AWS_ACCOUNT_ID=012345678901
aws lambda create-function \
--function-name StreamingFromEvent \
--zip-file fileb://.build/plugins/AWSLambdaPackager/outputs/AWSLambdaPackager/StreamingFromEvent/StreamingFromEvent.zip \
--runtime provided.al2 \
--handler provided \
--architectures arm64 \
--role arn:aws:iam::${AWS_ACCOUNT_ID}:role/lambda_basic_execution
```

> [!IMPORTANT] 
> The timeout value must be bigger than the time it takes for your function to stream its output. Otherwise, the Lambda control plane will terminate the execution environment before your code has a chance to finish writing the stream. Here, the sample function stream responses during 10 seconds and we set the timeout for 15 seconds.

The `--architectures` flag is only required when you build the binary on an Apple Silicon machine (Apple M1 or more recent). It defaults to `x64`.

Be sure to set `AWS_ACCOUNT_ID` with your actual AWS account ID (for example: 012345678901).

### Step 2: Give permission to invoke that function through a URL

Anyone with a valid signature from your AWS account will have permission to invoke the function through its URL.

```bash
aws lambda add-permission \
  --function-name StreamingFromEvent \
  --action lambda:InvokeFunctionUrl \
  --principal ${AWS_ACCOUNT_ID} \
  --function-url-auth-type AWS_IAM \
  --statement-id allowURL
```  

### Step 3: Create the URL 

This creates [a URL with IAM authentication](https://docs.aws.amazon.com/lambda/latest/dg/urls-auth.html). Only calls with a valid signature will be authorized.

```bash
aws lambda create-function-url-config \
  --function-name StreamingFromEvent \
  --auth-type AWS_IAM \
  --invoke-mode RESPONSE_STREAM 
```
This call returns various information, including the URL to invoke your function.

```json
{
    "FunctionUrl": "https://ul3nf4dogmgyr7ffl5r5rs22640fwocc.lambda-url.us-east-1.on.aws/",
    "FunctionArn": "arn:aws:lambda:us-east-1:012345678901:function:StreamingFromEvent",
    "AuthType": "AWS_IAM",
    "CreationTime": "2024-10-22T07:57:23.112599Z",
    "InvokeMode": "RESPONSE_STREAM"
}
```

### Invoke your Lambda function

To invoke the Lambda function, use `curl` with the AWS Sigv4 option to generate the signature.

Read the [AWS Credentials and Signature](../README.md/#AWS-Credentials-and-Signature) section for more details about the AWS Sigv4 protocol and how to obtain AWS credentials.

When you have the `aws` command line installed and configured, you will find the credentials in the `~/.aws/credentials` file.

```bash
URL=https://ul3nf4dogmgyr7ffl5r5rs22640fwocc.lambda-url.us-east-1.on.aws/
REGION=us-east-1

# Set the AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, and AWS_SESSION_TOKEN environment variables
eval $(aws configure export-credentials --format env)

curl --user "${AWS_ACCESS_KEY_ID}":"${AWS_SECRET_ACCESS_KEY}"   \
     --aws-sigv4 "aws:amz:${REGION}:lambda" \
     -H "x-amz-security-token: ${AWS_SESSION_TOKEN}" \
     --no-buffer \
     --header "Content-Type: application/json" \
     --data '{"count": 3, "message": "Hello World!", "delayMs": 1000}' \
     "$URL"  
```

This should output the following result, with configurable delays between each message:

```
[2024-07-15T05:00:00Z] Message 1/3: Hello World!
[2024-07-15T05:00:01Z] Message 2/3: Hello World!
[2024-07-15T05:00:02Z] Message 3/3: Hello World!
✅ Successfully sent 3 messages
```

### Undeploy

When done testing, you can delete the Lambda function with this command.

```bash
aws lambda delete-function --function-name StreamingFromEvent
```

## Deploy with AWS SAM 

Alternatively, you can use [AWS SAM](https://aws.amazon.com/serverless/sam/) to deploy the Lambda function.

**Prerequisites** : Install the [SAM CLI](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html)

### SAM Template

The template file is provided as part of the example in the `template.yaml` file. It defines a Lambda function based on the binary ZIP file. It creates the function url with IAM authentication and sets the function timeout to 15 seconds.

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Transform: AWS::Serverless-2016-10-31
Description: SAM Template for StreamingFromEvent Example

Resources:
  # Lambda function
  StreamingNumbers:
    Type: AWS::Serverless::Function
    Properties:
      CodeUri: .build/plugins/AWSLambdaPackager/outputs/AWSLambdaPackager/StreamingFromEvent/StreamingFromEvent.zip
      Timeout: 15
      Handler: swift.bootstrap  # ignored by the Swift runtime
      Runtime: provided.al2
      MemorySize: 128
      Architectures:
        - arm64
      FunctionUrlConfig:
        AuthType: AWS_IAM
        InvokeMode: RESPONSE_STREAM

Outputs:
  # print Lambda function URL
  LambdaURL:
    Description: Lambda URL
    Value: !GetAtt StreamingNumbersUrl.FunctionUrl
```

### Deploy with SAM 

```bash
sam deploy \
--resolve-s3 \
--template-file template.yaml \
--stack-name StreamingFromEvent \
--capabilities CAPABILITY_IAM 
```

The URL of the function is provided as part of the output.

```
CloudFormation outputs from deployed stack
-----------------------------------------------------------------------------------------------------------------------------
Outputs                                                                                                                                   
-----------------------------------------------------------------------------------------------------------------------------
Key                 LambdaURL                                                                                                             
Description         Lambda URL                                                                                                            
Value               https://gaudpin2zjqizfujfnqxstnv6u0czrfu.lambda-url.us-east-1.on.aws/                                                 
-----------------------------------------------------------------------------------------------------------------------------
```

Once the function is deployed, you can invoke it with `curl`, similarly to what you did when deploying with the AWS CLI.

```bash
# Set the AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, and AWS_SESSION_TOKEN environment variables
eval $(aws configure export-credentials --format env)

curl -X POST \
     --data '{"count": 3, "message": "Hello World!", "delayMs": 1000}' \
     --user "$AWS_ACCESS_KEY_ID":"$AWS_SECRET_ACCESS_KEY"   \
     --aws-sigv4 "aws:amz:${REGION}:lambda" \
     -H "x-amz-security-token: $AWS_SESSION_TOKEN" \
     --no-buffer \
     "$URL"
```

### Undeploy with SAM 

When done testing, you can delete the infrastructure with this command.

```bash
sam delete 
```

## ⚠️ Security and Reliability Notice

These are example applications for demonstration purposes. When deploying such infrastructure in production environments, we strongly encourage you to follow these best practices for improved security and resiliency:

- Enable access logging on API Gateway ([documentation](https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-logging.html))
- Ensure that AWS Lambda function is configured for function-level concurrent execution limit ([concurrency documentation](https://docs.aws.amazon.com/lambda/latest/dg/lambda-concurrency.html), [configuration guide](https://docs.aws.amazon.com/lambda/latest/dg/configuration-concurrency.html))
- Check encryption settings for Lambda environment variables ([documentation](https://docs.aws.amazon.com/lambda/latest/dg/configuration-envvars-encryption.html))
- Ensure that AWS Lambda function is configured for a Dead Letter Queue (DLQ) ([documentation](https://docs.aws.amazon.com/lambda/latest/dg/invocation-async-retain-records.html#invocation-dlq))
- Ensure that AWS Lambda function is configured inside a VPC when it needs to access private resources ([documentation](https://docs.aws.amazon.com/lambda/latest/dg/configuration-vpc.html), [code example](https://github.com/awslabs/swift-aws-lambda-runtime/tree/main/Examples/ServiceLifecycle%2BPostgres))