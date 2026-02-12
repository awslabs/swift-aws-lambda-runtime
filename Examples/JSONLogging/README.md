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
      CodeUri: .build/plugins/AWSLambdaPackager/outputs/AWSLambdaPackager/JSONLogging/JSONLogging.zip
      Handler: swift.bootstrap
      Runtime: provided.al2
      Architectures:
        - arm64
      LoggingConfig:
        LogFormat: JSON
        ApplicationLogLevel: INFO  # TRACE | DEBUG | INFO | WARN | ERROR | FATAL
        SystemLogLevel: INFO       # DEBUG | INFO | WARN
```

## Test Locally

Start the local server:

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
swift package archive --allow-network-connections docker
```

The deployment package will be at:
`.build/plugins/AWSLambdaPackager/outputs/AWSLambdaPackager/JSONLogging/JSONLogging.zip`

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
      CodeUri: .build/plugins/AWSLambdaPackager/outputs/AWSLambdaPackager/JSONLogging/JSONLogging.zip
      Timeout: 60
      Handler: swift.bootstrap
      Runtime: provided.al2
      MemorySize: 128
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
sam build
sam deploy --guided
```

## Deploy with AWS CLI

```bash
aws lambda create-function \
  --function-name JSONLoggingExample \
  --zip-file fileb://.build/plugins/AWSLambdaPackager/outputs/AWSLambdaPackager/JSONLogging/JSONLogging.zip \
  --runtime provided.al2 \
  --handler swift.bootstrap \
  --architectures arm64 \
  --role arn:aws:iam::<YOUR_ACCOUNT_ID>:role/lambda_basic_execution \
  --logging-config LogFormat=JSON,ApplicationLogLevel=DEBUG,SystemLogLevel=INFO
```

## Invoke

```bash
aws lambda invoke \
  --function-name JSONLoggingExample \
  --payload '{"name":"Alice","level":"debug"}' \
  response.json && cat response.json
```

## Query Logs with CloudWatch Logs Insights

With JSON formatted logs, you can use powerful queries:

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

# AWS CLI deployment
aws lambda delete-function --function-name JSONLoggingExample
```

## ⚠️ Important Notes

- JSON logging adds metadata, which increases log size
- Default log level is `INFO` when JSON format is enabled
- For Python functions, the default changes from `WARN` to `INFO` with JSON format
- Logs are only formatted as JSON in the Lambda environment, not in local testing (unless you set `AWS_LAMBDA_LOG_FORMAT=JSON`)
