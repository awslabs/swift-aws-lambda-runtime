# Log and monitor Swift Lambda functions

AWS Lambda automatically monitors Lambda functions on your behalf and sends logs to Amazon CloudWatch. Your Lambda function comes with a CloudWatch Logs log group and a log stream for each instance of your function. The Lambda runtime environment sends details about each invocation to the log stream, and relays logs and other output from your function's code. For more information, see [Sending Lambda function logs to CloudWatch Logs](https://docs.aws.amazon.com/lambda/latest/dg/monitoring-cloudwatchlogs.html). This page describes how to produce log output from your Lambda function's code.

## Creating a function that writes logs

To output logs from your function code, use the `Logger` instance provided by the `LambdaContext`. The Swift AWS Lambda Runtime uses [swift-log](https://github.com/apple/swift-log), the logging API developed by Apple and the Swift Server Workgroup.

For every invocation, the runtime creates a request-scoped `Logger` carrying the invocation's `requestID` and `traceID` as metadata, and passes it to your handler as `context.logger`:

```swift
import AWSLambdaRuntime

struct Request: Decodable {
    let firstName: String
}

struct Response: Encodable {
    let message: String
}

let runtime = LambdaRuntime {
    (event: Request, context: LambdaContext) in

    context.logger.info("Swift function invoked")
    context.logger.info("Swift function responds to \(event.firstName)")

    return Response(message: "Hello, \(event.firstName)!")
}

try await runtime.run()
```

> **Note**: Avoid using `print()` for logging in Lambda functions. By default, `print()` output is buffered and may not be immediately sent to CloudWatch. The `context.logger` writes directly to `stderr`, ensuring logs are flushed immediately.

## Logging without passing the logger around

Threading `context.logger` through every function your handler calls is tedious. Instead, the runtime binds the request logger as the task-local `Logger.current` for the duration of the handler call. Code anywhere in the handler's call tree can read `Logger.current` and inherit the invocation's metadata, without a `LambdaContext` or `Logger` parameter:

```swift
import Logging

func validate(_ event: Request) {
    // No logger parameter — reads the task-local logger bound by the runtime.
    Logger.current.debug("Validating request")
}

let runtime = LambdaRuntime {
    (event: Request, context: LambdaContext) in

    validate(event)  // its log lines still carry this invocation's requestID / traceID
    return Response(message: "Hello, \(event.firstName)!")
}

try await runtime.run()
```

Inside the handler itself, `context.logger` and `Logger.current` are equivalent. Use whichever reads better; `context.logger` is more explicit at the call site.

> **Note**: Task-local values propagate through structured concurrency (`async let`, `withTaskGroup`, child `Task {}`) but are **not** inherited by `Task.detached`. You must capture the logger explicitly across a detached boundary.

## Log levels

The Swift `Logger` supports the following log levels, ordered from least severe to most severe:

- `trace`
- `debug`
- `info`
- `notice`
- `warning`
- `error`
- `critical`

By default, the log level is set to `info`, meaning that `trace` and `debug` logs are ignored.

## Configuring the log format and level

The log format and level are controlled by environment variables set on your Lambda function:

- **`AWS_LAMBDA_LOG_FORMAT`**: Set to `Text` (default) or `JSON` to control the output format.
- **`AWS_LAMBDA_LOG_LEVEL`** or **`LOG_LEVEL`**: Set to one of the log levels listed above (e.g. `debug`, `info`, `warning`).

To change the log level, set the `LOG_LEVEL` environment variable on your Lambda function in the AWS Console or in your deployment template:

```yaml
Resources:
  MyFunction:
    Type: AWS::Serverless::Function
    Properties:
      # ...
      Environment:
        Variables:
          LOG_LEVEL: debug
          AWS_LAMBDA_LOG_FORMAT: JSON
```

## Implementing structured logging

When `AWS_LAMBDA_LOG_FORMAT` is set to `JSON`, each log line is emitted as a valid JSON object. The runtime automatically includes the `requestID` and `traceID` metadata fields. You can add additional metadata to your log messages:

```swift
let runtime = LambdaRuntime {
    (event: Request, context: LambdaContext) in

    // Log with additional metadata
    context.logger.info(
        "Processing request",
        metadata: ["firstName": "\(event.firstName)"]
    )

    // Different log levels
    context.logger.debug("Debug information for development")
    context.logger.warning("Something might be wrong")
    context.logger.error("An error occurred")

    return Response(message: "Hello, \(event.firstName)!")
}

try await runtime.run()
```

When this Swift function is invoked with `AWS_LAMBDA_LOG_FORMAT=JSON`, it produces log lines similar to the following in CloudWatch:

```json
{"level":"info","message":"Processing request","metadata":{"firstName":"David","requestID":"a1234-5678-90ab","traceID":"Root=1-abc-def"}}
{"level":"debug","message":"Debug information for development","metadata":{"requestID":"a1234-5678-90ab","traceID":"Root=1-abc-def"}}
```

## Binding a logger at application startup

You can bind a logger before and around `runtime.run()`. This is useful when combining Lambda with other services, such as [Swift Service Lifecycle](https://github.com/swift-server/swift-service-lifecycle):

```swift
import Logging
import AWSLambdaRuntime

let logger = Logger(label: "my-function")
try await withLogger(logger) { _ in
    let runtime = LambdaRuntime { (event: Request, context: LambdaContext) in
        context.logger.info("Processing request")
        return Response(message: "Hello!")
    }
    try await runtime.run()
}
```

For information about configuring log formats in Lambda, see [Configuring JSON and plain text log formats](https://docs.aws.amazon.com/lambda/latest/dg/monitoring-cloudwatchlogs-advanced.html).
