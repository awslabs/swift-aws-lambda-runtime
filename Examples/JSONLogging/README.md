# JSON Logging Example

This example demonstrates how to use structured JSON logging with AWS Lambda functions written in Swift. When configured with JSON log format, your logs are automatically structured as JSON objects, making them easier to search, filter, and analyze in CloudWatch Logs.

## Features

- Structured JSON log output
- Automatic inclusion of request ID and trace ID
- Support for all log levels (TRACE, DEBUG, INFO, WARN, ERROR, FATAL)
- Custom metadata in logs
- Compatible with CloudWatch Logs Insights queries

## Code

The Lambda function demonstrates various logging levels and metadata usage. When `AWS_LAMBDA_LOG_FORMAT` is set to `JSON`, all logs are automatically formatted as JSON objects with the following structure:

```json
{
  "timestamp": "2024-10-27T19:17:45.586Z",
  "level": "INFO",
  "message": "Processing request for Alice",
  "requestId": "79b4f56e-95b1-4643-9700-2807f4e68189",
  "traceId": "Root=1-67890abc-def12345678901234567890a"
}
```

## Logging from helper functions with `Logger.current`

The runtime binds the per-invocation logger as the task-local [`Logger.current`](https://github.com/apple/swift-log) for the duration of each handler call. This means functions your handler calls can log with the request's metadata (request ID, trace ID) **without** receiving a `LambdaContext` or `Logger` parameter:

```swift
func validate(_ event: Request) {
    Logger.current.debug("Validating request", metadata: ["name": .string(event.name)])
    if event.name.isEmpty {
        Logger.current.warning("Received a request with an empty name")
    }
}

let runtime = LambdaRuntime { (event: Request, context: LambdaContext) in
    context.logger.info("Processing request for \(event.name)")
    validate(event)  // its logs carry this invocation's request ID and trace ID automatically
    // ...
}
```

This keeps your business code clean — no need to thread a logger through every function signature. Inside the handler itself, `context.logger` and `Logger.current` are equivalent.

> **Notes**
> - Automatic binding requires **Swift 6.2 or later**. On older toolchains, `Logger.current` falls back to the process-wide default logger (without the request metadata).
> - Task-local values propagate through structured concurrency (`async let`, `withTaskGroup`, child `Task {}`) but are **not** inherited by `Task.detached` — capture the logger explicitly across a detached boundary.

## Configuration

### Environment Variables

- `AWS_LAMBDA_LOG_FORMAT`: Set to `JSON` for structured logging (default: `Text`)
- `AWS_LAMBDA_LOG_LEVEL`: Control which logs are sent to CloudWatch
  - Valid values: `TRACE`, `DEBUG`, `INFO`, `WARN`, `ERROR`, `FATAL`
  - Default: `INFO` when JSON format is enabled

### SAM Template Configuration

Add the `LoggingConfig` property to your Lambda function:

```yaml
Resources:
  JSONLoggingFunction:
    Type: AWS::Serverless::Function
    Properties:
      CodeUri: .build/plugins/AWSLambdaBuilder/outputs/AWSLambdaBuilder/JSONLogging/JSONLogging.zip
      Handler: swift.bootstrap
      Runtime: provided.al2023
      Architectures:
        - arm64
      LoggingConfig:
        LogFormat: JSON
        ApplicationLogLevel: INFO  # TRACE | DEBUG | INFO | WARN | ERROR | FATAL
        SystemLogLevel: INFO       # DEBUG | INFO | WARN
```

## Test Locally

Start the local server with TEXT logging:

```bash
swift run
```

Send test requests:

```bash
# Basic request
curl -d '{"name":"Alice"}' http://127.0.0.1:7000/invoke

# Request with custom level
curl -d '{"name":"Bob","level":"debug"}' http://127.0.0.1:7000/invoke

# Trigger error logging
curl -d '{"name":"error"}' http://127.0.0.1:7000/invoke
```

To test with JSON logging locally, set the environment variable:

```bash
AWS_LAMBDA_LOG_FORMAT=JSON swift run
```

## Build & Package

```bash
swift build
swift package --allow-network-connections docker lambda-build
```

The deployment package will be at:
`.build/plugins/AWSLambdaBuilder/outputs/AWSLambdaBuilder/JSONLogging/JSONLogging.zip`

## Deploy with SAM

Create a `template.yaml` file:

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Transform: AWS::Serverless-2016-10-31
Description: JSON Logging Example

Resources:
  JSONLoggingFunction:
    Type: AWS::Serverless::Function
    Properties:
      CodeUri: .build/plugins/AWSLambdaBuilder/outputs/AWSLambdaBuilder/JSONLogging/JSONLogging.zip
      Timeout: 60
      Handler: swift.bootstrap
      Runtime: provided.al2023
      Architectures:
        - arm64
      LoggingConfig:
        LogFormat: JSON
        ApplicationLogLevel: DEBUG
        SystemLogLevel: INFO

Outputs:
  FunctionName:
    Description: Lambda Function Name
    Value: !Ref JSONLoggingFunction
```

Deploy:

```bash
sam deploy --guided
```

## Deploy with AWS CLI

As an alternative to SAM, you can use the `lambda-deploy` plugin:

```bash
swift package --allow-network-connections all:443 lambda-deploy
```

This creates the Lambda function, provisions the necessary IAM role, and uploads the deployment package.

After deploying, configure logging format:

```bash
aws lambda update-function-configuration \
  --function-name JSONLogging \
  --logging-config LogFormat=JSON,ApplicationLogLevel=DEBUG,SystemLogLevel=INFO
```

## Invoke

```bash
aws lambda invoke \
  --function-name JSONLoggingExample \
  --cli-binary-format raw-in-base64-out \
  --payload '{"name":"Alice","level":"debug"}' \
  response.json && cat response.json && rm response.json
```

## Query Logs with CloudWatch Logs Insights

With JSON formatted logs, you can use powerful queries in [CloudWatch Logs Insights](https://console.aws.amazon.com/cloudwatch/home#logsV2:logs-insights).

### Using the AWS Console

1. Open the [CloudWatch Logs Insights console](https://console.aws.amazon.com/cloudwatch/home#logsV2:logs-insights)
2. In the "Select log group(s)" dropdown, choose the log group for your Lambda function (typically `/aws/lambda/JSONLoggingExample`)
3. Type or paste one of the queries below into the query editor
4. Adjust the time range in the top-right corner to cover the period you're interested in
5. Click "Run query"

```
# Find all ERROR level logs
fields @timestamp, level, message, requestId
| filter level = "ERROR"
| sort @timestamp desc

# Find logs for a specific request
fields @timestamp, level, message
| filter requestId = "79b4f56e-95b1-4643-9700-2807f4e68189"
| sort @timestamp asc

# Count logs by level
stats count() by level

# Find logs with specific metadata
fields @timestamp, message, metadata.errorType
| filter metadata.errorType = "SimulatedError"
```

### Using the AWS CLI

You can also run Logs Insights queries from the command line. Each query is a two-step process: start the query, then fetch the results.

```bash
# 1. Start a query (adjust --start-time and --end-time as needed)
QUERY_ID=$(aws logs start-query \
  --log-group-name '/aws/lambda/JSONLoggingExample' \
  --start-time $(date -v-1H +%s) \
  --end-time $(date +%s) \
  --query-string 'fields @timestamp, level, message | filter level = "ERROR" | sort @timestamp desc' \
  --query 'queryId' --output text)

# 2. Wait a moment for the query to complete, then get the results
sleep 2
aws logs get-query-results --query-id "$QUERY_ID"
```

A few more examples:

```bash
# Count logs by level over the last 24 hours
QUERY_ID=$(aws logs start-query \
  --log-group-name '/aws/lambda/JSONLoggingExample' \
  --start-time $(date -v-24H +%s) \
  --end-time $(date +%s) \
  --query-string 'stats count() by level' \
  --query 'queryId' --output text)
sleep 2
aws logs get-query-results --query-id "$QUERY_ID"

# Find logs with a specific error type in the last hour
QUERY_ID=$(aws logs start-query \
  --log-group-name '/aws/lambda/JSONLoggingExample' \
  --start-time $(date -v-1H +%s) \
  --end-time $(date +%s) \
  --query-string 'fields @timestamp, message, metadata.errorType | filter metadata.errorType = "SimulatedError"' \
  --query 'queryId' --output text)
sleep 2
aws logs get-query-results --query-id "$QUERY_ID"
```

> **Note**: On Linux, replace `date -v-1H +%s` with `date -d '1 hour ago' +%s` (and similarly for other time offsets).

## Log Levels

The runtime maps Swift's `Logger.Level` to AWS Lambda log levels:

| Swift Logger.Level | JSON Output | Description |
|-------------------|-------------|-------------|
| `.trace` | `TRACE` | Most detailed |
| `.debug` | `DEBUG` | Debug information |
| `.info` | `INFO` | Informational |
| `.notice` | `INFO` | Notable events |
| `.warning` | `WARN` | Warning conditions |
| `.error` | `ERROR` | Error conditions |
| `.critical` | `FATAL` | Critical failures |

## Benefits of JSON Logging

1. **Structured Data**: Logs are key-value pairs, not plain text
2. **Easy Filtering**: Query specific fields in CloudWatch Logs Insights
3. **Automatic Context**: Request ID and trace ID included automatically
4. **Metadata Support**: Add custom fields to logs
5. **No Double Encoding**: Already-JSON logs aren't double-encoded
6. **Better Analysis**: Automated log analysis and alerting

## Clean Up

```bash
# SAM deployment
sam delete

# Plugin deployment
swift package --allow-network-connections all:443 lambda-deploy --delete
```

## ⚠️ Important Notes

- JSON logging adds metadata, which increases log size
- Default log level is `INFO` when JSON format is enabled
- For Python functions, the default changes from `WARN` to `INFO` with JSON format
- Logs are only formatted as JSON in the Lambda environment, not in local testing (unless you set `AWS_LAMBDA_LOG_FORMAT=JSON`)
