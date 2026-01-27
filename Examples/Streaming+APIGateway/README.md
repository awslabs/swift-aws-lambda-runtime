# Streaming Lambda function with API Gateway

You can configure your Lambda function to stream response payloads back to clients through Amazon API Gateway. Response streaming can benefit latency sensitive applications by improving time to first byte (TTFB) performance. This is because you can send partial responses back to the client as they become available. Additionally, you can use response streaming to build functions that return larger payloads. Response stream payloads have a soft limit of 200 MB as compared to the 6 MB limit for buffered responses. Streaming a response also means that your function doesn't need to fit the entire response in memory. For very large responses, this can reduce the amount of memory you need to configure for your function.

Streaming responses incurs a cost. For more information, see [AWS Lambda Pricing](https://aws.amazon.com/lambda/pricing/).

You can stream responses through Lambda function URLs, **Amazon API Gateway**, the AWS SDK, or using the Lambda [InvokeWithResponseStream](https://docs.aws.amazon.com/lambda/latest/dg/API_InvokeWithResponseStream.html) API. In this example, we expose the streaming Lambda function through **API Gateway REST API** with response streaming enabled.

For more information about configuring Lambda response streaming with API Gateway, see [Configure a Lambda proxy integration with payload response streaming](https://docs.aws.amazon.com/apigateway/latest/developerguide/response-streaming-lambda-configure.html).

## Code 

The sample code creates a `SendNumbersWithPause` struct that conforms to the `StreamingLambdaHandler` protocol provided by the Swift AWS Lambda Runtime.

The `handle(...)` method of this protocol receives incoming events as a Swift NIO `ByteBuffer` and returns the output as a `ByteBuffer`.

The response is streamed through the `LambdaResponseStreamWriter`, which is passed as an argument in the `handle` function. 

### Setting HTTP Status Code and Headers

Before streaming the response body, you can set the HTTP status code and headers using the `writeStatusAndHeaders(_:)` method:

```swift
try await responseWriter.writeStatusAndHeaders(
    StreamingLambdaStatusAndHeadersResponse(
        statusCode: 200,
        headers: [
            "Content-Type": "text/plain",
            "x-my-custom-header": "streaming-example"
        ]
    )
)
```

The `StreamingLambdaStatusAndHeadersResponse` structure allows you to specify:
- **statusCode**: HTTP status code (e.g., 200, 404, 500)
- **headers**: Dictionary of single-value HTTP headers (optional)

### Streaming the Response Body

After setting headers, you can stream the response body by calling the `write(_:)` function of the `LambdaResponseStreamWriter` with partial data repeatedly before finally closing the response stream by calling `finish()`. Developers can also choose to return the entire output and not stream the response by calling `writeAndFinish(_:)`.

```swift
// Stream data in chunks
for i in 1...3 {
    try await responseWriter.write(ByteBuffer(string: "Number: \(i)\n"))
    try await Task.sleep(for: .milliseconds(1000))
}

// Close the response stream
try await responseWriter.finish()
```

An error is thrown if `finish()` is called multiple times or if it is called after having called `writeAndFinish(_:)`.

### Example Usage Patterns

The example includes a **SendNumbersWithPause** handler that demonstrates basic streaming with headers, sending numbers with delays

The `handle(...)` method is marked as `mutating` to allow handlers to be implemented with a `struct`.

Once the struct is created and the `handle(...)` method is defined, the sample code creates a `LambdaRuntime` struct and initializes it with the handler just created. Then, the code calls `run()` to start the interaction with the AWS Lambda control plane.

## Build & Package 

To build & archive the package, type the following commands.

```bash
swift package archive --allow-network-connections docker
```

If there is no error, there is a ZIP file ready to deploy. 
The ZIP file is located at `.build/plugins/AWSLambdaPackager/outputs/AWSLambdaPackager/StreamingNumbers/StreamingNumbers.zip`

## Test locally

You can test the function locally before deploying:

```bash
swift run 

# In another terminal, test with curl:
curl -v --output response.txt \
  --header "Content-Type: application/json" \
  --data '"this is not used"' \
  http://127.0.0.1:7000/invoke
```

## Deploy with AWS SAM 

[AWS SAM](https://aws.amazon.com/serverless/sam/) provides a streamlined way to deploy Lambda functions with API Gateway streaming support.

**Prerequisites**: Install the [SAM CLI](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html)

### SAM Template

The template file is provided as part of the example in the `template.yaml` file. It defines:

- A Lambda function with streaming support
- An API Gateway REST API configured for response streaming
- An IAM role that allows API Gateway to invoke the Lambda function with streaming
- The `/stream` endpoint that accepts any HTTP method

Key configuration details:

```yaml
Resources:
  StreamingNumbers:
    Type: AWS::Serverless::Function
    Properties:
      CodeUri: .build/plugins/AWSLambdaPackager/outputs/AWSLambdaPackager/StreamingNumbers/StreamingNumbers.zip
      Timeout: 60  # Must be bigger than the time it takes to stream the output
      Handler: swift.bootstrap
      Runtime: provided.al2
      MemorySize: 128
      Architectures:
        - arm64
      Events:
        StreamingApi:
          Type: Api
          Properties:
            RestApiId: !Ref StreamingApi
            Path: /stream
            Method: ANY

  StreamingApi:
    Type: AWS::Serverless::Api
    Properties:
      StageName: prod
      DefinitionBody:
        openapi: "3.0.1"
        info:
          title: "StreamingAPI"
          version: "1.0"
        paths:
          /stream:
            x-amazon-apigateway-any-method:
              x-amazon-apigateway-integration:
                httpMethod: POST
                type: aws_proxy
                # Special URI for streaming invocations
                uri: !Sub "arn:aws:apigateway:${AWS::Region}:lambda:path/2021-11-15/functions/${StreamingNumbers.Arn}/response-streaming-invocations"
                timeoutInMillis: 60000
                responseTransferMode: STREAM  # Enable streaming
                credentials: !GetAtt ApiGatewayLambdaInvokeRole.Arn
```

> [!IMPORTANT] 
> The timeout value must be bigger than the time it takes for your function to stream its output. Otherwise, the Lambda control plane will terminate the execution environment before your code has a chance to finish writing the stream. The sample function streams responses over 3 seconds, and we set the timeout to 60 seconds for safety.

### Deploy with SAM 

```bash
sam deploy \
  --resolve-s3 \
  --template-file template.yaml \
  --stack-name StreamingNumbers \
  --capabilities CAPABILITY_IAM
```

The API Gateway endpoint URL is provided as part of the output:

```
CloudFormation outputs from deployed stack
-----------------------------------------------------------------------------------------------------------------------------
Outputs                                                                                                                                   
-----------------------------------------------------------------------------------------------------------------------------
Key                 ApiUrl                                                                                                             
Description         API Gateway endpoint URL for streaming                                                                                                            
Value               https://abc123xyz.execute-api.us-east-1.amazonaws.com/prod/stream                                                 
-----------------------------------------------------------------------------------------------------------------------------
Key                 LambdaArn                                                                                                             
Description         Lambda Function ARN                                                                                                            
Value               arn:aws:lambda:us-east-1:123456789012:function:StreamingNumbers-StreamingNumbers-ABC123                                                 
-----------------------------------------------------------------------------------------------------------------------------
```

### Invoke the API Gateway endpoint

To invoke the streaming API through API Gateway, use `curl` with AWS Sigv4 authentication:

#### Get AWS Credentials

Read the [AWS Credentials and Signature](../README.md/#AWS-Credentials-and-Signature) section for more details about the AWS Sigv4 protocol and how to obtain AWS credentials.

When you have the `aws` command line installed and configured, you will find the credentials in the `~/.aws/credentials` file.

#### Invoke with authentication

```bash
# Set your values
API_URL=https://abc123xyz.execute-api.us-east-1.amazonaws.com/prod/stream
REGION=us-east-1
# Set the AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, and AWS_SESSION_TOKEN environment variables
eval $(aws configure export-credentials --format env)

# Invoke the streaming API
curl "$API_URL" \
     --user "$AWS_ACCESS_KEY_ID:$AWS_SECRET_ACCESS_KEY" \
     --aws-sigv4 "aws:amz:$REGION:execute-api" \
     -H "x-amz-security-token: $AWS_SESSION_TOKEN" \
     --no-buffer
```

> [!NOTE]
> - The `--no-buffer` flag is important for streaming responses - it ensures curl displays data as it arrives
> - The service name for API Gateway is `execute-api` (not `lambda`)
> - If you're not using temporary credentials (session token), you can omit the `x-amz-security-token` header

This should output the following result, with a one-second delay between each number:

```
1
2
3
Streaming complete!
```

### Alternative: Test without authentication (not recommended for production)

If you want to test without authentication, you can modify the API Gateway to use `NONE` auth type. However, this is **not recommended for production** as it exposes your API publicly.

To enable public access for testing, modify the `template.yaml`:

```yaml
StreamingApi:
  Type: AWS::Serverless::Api
  Properties:
    StageName: prod
    Auth:
      DefaultAuthorizer: NONE
    # ... rest of configuration
```

Then you can invoke without credentials:

```bash
curl https://abc123xyz.execute-api.us-east-1.amazonaws.com/prod/stream --no-buffer
```

### Undeploy with SAM 

When done testing, you can delete the infrastructure with this command:

```bash
sam delete --stack-name StreamingNumbers
```

## Payload decoding

When you invoke the function through API Gateway, the incoming `ByteBuffer` contains a payload that gives developer access to the underlying HTTP call. The payload contains information about the HTTP verb used, the headers received, the authentication method, and more.

The [AWS documentation contains the details](https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-lambda-proxy-integrations.html#api-gateway-simple-proxy-for-lambda-input-format) of the payload format. The [Swift Lambda Event library](https://github.com/awslabs/swift-aws-lambda-events) contains an [`APIGatewayV2Request` type](https://github.com/awslabs/swift-aws-lambda-events/blob/main/Sources/AWSLambdaEvents/APIGatewayV2.swift) ready to use in your projects.

Here is an example of API Gateway proxy integration payload:

```json
{
    "version": "2.0",
    "routeKey": "ANY /stream",
    "rawPath": "/prod/stream",
    "rawQueryString": "",
    "headers": {
        "accept": "*/*",
        "content-length": "0",
        "host": "abc123xyz.execute-api.us-east-1.amazonaws.com",
        "user-agent": "curl/8.7.1",
        "x-amzn-trace-id": "Root=1-67890abc-1234567890abcdef",
        "x-forwarded-for": "203.0.113.1",
        "x-forwarded-port": "443",
        "x-forwarded-proto": "https"
    },
    "requestContext": {
        "accountId": "123456789012",
        "apiId": "abc123xyz",
        "domainName": "abc123xyz.execute-api.us-east-1.amazonaws.com",
        "domainPrefix": "abc123xyz",
        "http": {
            "method": "GET",
            "path": "/prod/stream",
            "protocol": "HTTP/1.1",
            "sourceIp": "203.0.113.1",
            "userAgent": "curl/8.7.1"
        },
        "requestId": "abc123-def456-ghi789",
        "routeKey": "ANY /stream",
        "stage": "prod",
        "time": "30/Nov/2025:10:30:00 +0000",
        "timeEpoch": 1733000000000
    },
    "isBase64Encoded": false
}
```

## How API Gateway Streaming Works

When you configure API Gateway with `responseTransferMode: STREAM`:

1. **Special Lambda URI**: API Gateway uses the `/response-streaming-invocations` endpoint instead of the standard `/invocations` endpoint
2. **InvokeWithResponseStream API**: API Gateway calls the Lambda `InvokeWithResponseStream` API instead of the standard `Invoke` API
3. **Chunked Transfer**: Responses are sent using HTTP chunked transfer encoding, allowing data to flow as it's generated
4. **IAM Permissions**: The API Gateway execution role needs both `lambda:InvokeFunction` and `lambda:InvokeWithResponseStream` permissions

## ⚠️ Security and Reliability Notice

These are example applications for demonstration purposes. When deploying such infrastructure in production environments, we strongly encourage you to follow these best practices for improved security and resiliency:

- **Enable access logging on API Gateway** ([documentation](https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-logging.html))
- **Configure API Gateway throttling** to protect against abuse ([documentation](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-request-throttling.html))
- **Use AWS WAF** with API Gateway for additional security ([documentation](https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-control-access-aws-waf.html))
- **Ensure Lambda function has concurrent execution limits** ([concurrency documentation](https://docs.aws.amazon.com/lambda/latest/dg/lambda-concurrency.html), [configuration guide](https://docs.aws.amazon.com/lambda/latest/dg/configuration-concurrency.html))
- **Enable encryption for Lambda environment variables** ([documentation](https://docs.aws.amazon.com/lambda/latest/dg/configuration-envvars-encryption.html))
- **Configure a Dead Letter Queue (DLQ)** for Lambda ([documentation](https://docs.aws.amazon.com/lambda/latest/dg/invocation-async-retain-records.html#invocation-dlq))
- **Use VPC configuration** when Lambda needs to access private resources ([documentation](https://docs.aws.amazon.com/lambda/latest/dg/configuration-vpc.html), [code example](https://github.com/awslabs/swift-aws-lambda-runtime/tree/main/Examples/ServiceLifecycle%2BPostgres))
- **Implement proper IAM authentication** instead of public access for production APIs
- **Enable CloudWatch Logs** for both API Gateway and Lambda for monitoring and debugging
