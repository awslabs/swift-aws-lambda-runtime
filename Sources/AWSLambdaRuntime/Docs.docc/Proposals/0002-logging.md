# Structured JSON Logging Support for swift-aws-lambda-runtime

AWS Lambda supports advanced logging controls that enable functions to emit logs in JSON structured format and control log level granularity. The Swift AWS Lambda Runtime should support these capabilities to provide developers with enhanced logging, filtering, and observability features.

## Overview

For more details, see the [AWS Lambda advanced logging controls documentation](https://docs.aws.amazon.com/lambda/latest/dg/monitoring-cloudwatchlogs-logformat.html).

Versions:

- v3 (2025-02-12): Add `LambdaManagedRuntime` in teh list of struct to modify
- v2 (2025-01-20): Make `LogHandler` public
- v1 (2025-01-18): Initial version

### Motivation

#### Current Limitations

##### Unstructured Logging Format

Currently, the Swift runtime emits logs in plaintext (unstructured) format only. This creates several limitations:

- No native support for JSON structured logging
- Difficult to query and filter logs programmatically
- Limited integration with CloudWatch Logs Insights
- Reduced observability capabilities compared to other Lambda runtimes

##### Limited Log Level Configuration

The current implementation supports log level control via the `LOG_LEVEL` environment variable, which works well for text format logging. However, AWS Lambda's new advanced logging controls introduce `AWS_LAMBDA_LOG_LEVEL` as the standard environment variable for log level configuration, particularly for JSON format logging. This creates a need to:

- Support both `LOG_LEVEL` (existing) and `AWS_LAMBDA_LOG_LEVEL` (new) with proper precedence
- Align with AWS Lambda's standard logging environment variables
- Maintain backward compatibility while supporting new AWS logging features

##### Limited Lambda Managed Instances Support

For Lambda Managed Instances, the log format is always JSON and cannot be changed. While Swift functions can work with Lambda Managed Instances, they will have their application logs automatically converted to JSON format by the Lambda service, which may not preserve the intended structure or metadata.

#### New Features

##### Support for JSON Structured Logging

AWS Lambda provides logging configuration through environment variables that custom runtimes should read and respect:

- `AWS_LAMBDA_LOG_FORMAT`: Controls output format (`Text` or `JSON`)
- `AWS_LAMBDA_LOG_LEVEL`: Controls log level granularity (`TRACE`, `DEBUG`, `INFO`, `WARN`, `ERROR`, `FATAL`)

##### Enhanced Log Level Configuration

The runtime should support both existing and new log level environment variables with proper precedence:

1. `AWS_LAMBDA_LOG_LEVEL` (new AWS standard, takes precedence for JSON format)
2. `LOG_LEVEL` (existing, maintained for backward compatibility and preferred for text format)

##### Enhanced Observability

JSON structured logs enable:

- Better integration with CloudWatch Logs Insights
- Programmatic log filtering and analysis
- Structured metadata inclusion (requestId, traceId, etc.)
- Cost optimization through dynamic log level control

### Proposed Solution

#### Environment Variable Configuration

The runtime will read logging configuration from Lambda-provided environment variables:

- When `AWS_LAMBDA_LOG_FORMAT=JSON`, emit structured JSON logs
- When `AWS_LAMBDA_LOG_FORMAT=Text` (or not set), maintain current plaintext behavior
- Support both `AWS_LAMBDA_LOG_LEVEL` and `LOG_LEVEL` with appropriate precedence based on format
- Maintain full backward compatibility with existing `LOG_LEVEL` usage

#### JSON Log Format Structure

When JSON format is enabled, application logs will follow this structure:

```json
{
  "timestamp": "2024-01-16T10:30:45.586Z",
  "level": "INFO",
  "message": "User authentication successful",
  "requestId": "8286a188-ba32-4475-8077-530cd35c09a9",
  "xrayTraceId": "1-5e1b4151-43a0913a12345678901234567"
}
```

Additional fields can be included based on the logging context and user-provided metadata.

#### Integration with swift-log

The Swift runtime uses the `swift-log` library for logging. The implementation will:

1. Create a custom `LogHandler` that supports JSON output when `AWS_LAMBDA_LOG_FORMAT=JSON`
2. Support both `AWS_LAMBDA_LOG_LEVEL` and `LOG_LEVEL` with format-appropriate precedence
3. Include Lambda-specific metadata (requestId, traceId, etc.)
4. Format logs according to the expected JSON structure
5. Continue using existing logging implementation when `AWS_LAMBDA_LOG_FORMAT=Text` (default)

#### Logger Initialization Strategy

The logger initialization will follow a two-phase approach:

##### Runtime Initialization (once per runtime instance)

```swift
let loggingConfiguration = LoggingConfiguration()
let runtimeLogger = loggingConfiguration.makeLogger(label: "LambdaRuntime")
```

##### Per-Request Logger Creation (once per invocation)

```swift
let requestLogger = loggingConfiguration.makeLogger(
    label: "Lambda",
    requestID: invocation.metadata.requestID,
    traceID: invocation.metadata.traceID
)
```

This approach ensures:

- Request-specific metadata is included in all logs for that invocation
- Efficient logger creation (reuses configuration, creates new logger instance)
- Proper isolation between concurrent invocations
- Structured concurrency compliance

### Detailed Solution

#### LoggingConfiguration

A new `LoggingConfiguration` struct will handle environment variable parsing and logger creation:

```swift
public struct LoggingConfiguration: Sendable {
    public enum LogFormat: String, CaseIterable {
        case text = "Text"
        case json = "JSON"
    }
    
    public let format: LogFormat
    public let level: Logger.Level
    
    public init()
    
    public func makeLogger(
        label: String,
        requestID: String? = nil,
        traceID: String? = nil
    ) -> Logger
}
```

Key features:

- Reads `AWS_LAMBDA_LOG_FORMAT` and both `AWS_LAMBDA_LOG_LEVEL` and `LOG_LEVEL` environment variables
- Implements log level precedence rules based on format (AWS standard for JSON, existing behavior for text)
- Provides factory method for creating loggers with request-specific metadata
- Thread-safe and sendable for concurrent access

#### JSONLogHandler

A new `LogHandler` implementation for JSON format logging:

```swift
public struct JSONLogHandler: LogHandler, Sendable {
    public var logLevel: Logger.Level
    public var metadata: Logger.Metadata
    
    public init(
        label: String,
        logLevel: Logger.Level = .info,
        requestID: String,
        traceID: String
    )
    
    public func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata: Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    )
}
```

Key features:

- Outputs JSON-formatted log entries to stdout
- Includes Lambda-specific metadata (requestId, traceId)
- Uses ISO 8601 timestamp format for compatibility
- Efficient JSON encoding using Foundation's JSONEncoder
- Cross-platform compatibility (macOS and Linux)

#### Runtime Integration

The `LambdaRuntime` will be updated to support the new logging configuration:

##### Runtime Initialization

```swift
public final class LambdaRuntime<Handler>: ServiceLifecycle.Service, Sendable
    where Handler: StreamingLambdaHandler
{
    public init(
        handler: sending Handler,
        loggingConfiguration: LoggingConfiguration = LoggingConfiguration(),
        eventLoop: EventLoop = Lambda.defaultEventLoop,
        logger: Logger? = nil
    )
}
```

##### Per-Request Logger Creation

In the main run loop, each invocation will receive a logger with request-specific metadata:

```swift
let requestLogger = loggingConfiguration.makeLogger(
    label: "Lambda",
    requestID: invocation.metadata.requestID,
    traceID: invocation.metadata.traceID
)

let context = LambdaContext(
    requestID: invocation.metadata.requestID,
    traceID: invocation.metadata.traceID,
    // ... other properties
    logger: requestLogger
)
```

#### Log Level Filtering

When log level environment variables are set, implement efficient log level filtering at the handler level to avoid unnecessary processing of log messages that won't be emitted. The precedence rules are:

- **JSON Format**: Prefer `AWS_LAMBDA_LOG_LEVEL`, fall back to `LOG_LEVEL`
- **Text Format**: Prefer `LOG_LEVEL` (existing behavior), support `AWS_LAMBDA_LOG_LEVEL` as alternative

### Implementation Considerations

#### Backward Compatibility

- When `AWS_LAMBDA_LOG_FORMAT=Text` (or not set), the runtime continues working exactly as it does today
- No breaking changes to existing APIs
- Existing log level configuration via `LOG_LEVEL` continues to work exactly as before
- New `AWS_LAMBDA_LOG_LEVEL` support is additive, not replacing existing functionality

#### Performance

- JSON encoding only occurs when `AWS_LAMBDA_LOG_FORMAT=JSON`
- Efficient logger creation with minimal per-request overhead
- Log level filtering prevents unnecessary message processing

#### Cross-Platform Support

- Uses conditional imports for Foundation compatibility
- Tested on both macOS and Linux (Amazon Linux 2)
- ISO 8601 timestamp formatting works consistently across platforms

#### System vs Application Logs

Custom runtimes are NOT responsible for emitting system logs (START, END, REPORT). The Lambda service handles these automatically. This implementation only affects application logs emitted through the `Logger` instance.

#### Logger Consistency Audit

**Current Status**: Code audit reveals mixed logger usage patterns that need to be addressed for consistent JSON logging:

**✅ Compliant Components:**
- `LambdaRuntimeClient` - properly receives logger from runtime
- `LambdaContext` - uses runtime-provided logger
- Handler adapters - accept logger parameters correctly

**⚠️ Issues Identified:**
2. **Default parameters** in convenience initializers create new loggers instead of using runtime logger
3. **Examples** create independent loggers (acceptable for demonstration)

**Required Changes:**
- Default logger parameters should be removed or use runtime logger
- All internal components must use the centralized logging configuration

This ensures consistent JSON formatting and log level control across all runtime components.

### Files to Create/Modify

#### New Files

1. `Sources/AWSLambdaRuntime/Logging/LoggingConfiguration.swift`
   - Environment variable parsing
   - Logger factory methods
   - Log level precedence logic

2. `Sources/AWSLambdaRuntime/Logging/JSONLogHandler.swift`
   - JSON log formatting
   - Lambda metadata integration
   - Cross-platform timestamp handling

#### Modified Files

1. `Sources/AWSLambdaRuntime/Runtime/LambdaRuntime.swift`
   - Add `LoggingConfiguration` parameter to initializers
   - Integrate per-request logger creation

2. `Sources/AWSLambdaRuntime/ManagedRuntime/LambdaManagedRuntime.swift`
   - Add `LoggingConfiguration` parameter to initializers
   - Integrate per-request logger creation

3. `Sources/AWSLambdaRuntime/Lambda.swift`
   - Update run loop to create request-specific loggers
   - Pass enhanced context to handlers

4. `Sources/AWSLambdaRuntime/LambdaContext.swift`
   - Ensure logger property uses request-specific instance

### Migration Considerations

#### For Existing Applications

- No code changes required for basic functionality
- Opt-in to JSON logging via environment variable
- Gradual migration path available

#### For New Applications

- JSON logging available from day one
- Enhanced observability capabilities
- Better integration with AWS tooling

### Alternatives Considered

#### Custom Logging Framework

We considered creating a Lambda-specific logging framework instead of extending swift-log. However, swift-log is the established standard in the Swift on Server ecosystem, and extending it provides better compatibility with existing libraries and tools.

#### Always-On JSON Logging

We considered making JSON the default format, but this would break backward compatibility. The environment variable approach allows for gradual adoption while maintaining compatibility.

### References

- [AWS Lambda Advanced Logging Controls](https://docs.aws.amazon.com/lambda/latest/dg/configuration-logging.html)
- [Building a custom runtime for AWS Lambda](https://docs.aws.amazon.com/lambda/latest/dg/runtimes-custom.html)
- [Swift Logging API](https://github.com/apple/swift-log)
- [Lambda Managed Instances](https://docs.aws.amazon.com/lambda/latest/dg/lambda-managed-instances.html)

### Related Issues

- [#634: Add Support for Structured JSON Logging](https://github.com/awslabs/swift-aws-lambda-runtime/issues/634)

### Labels

- enhancement
- logging
- observability
- aws-lambda

### Priority

Medium-High: This is a significant enhancement that improves observability and aligns with AWS Lambda best practices. It's also required for Lambda Managed Instances compatibility (which always use JSON format and cannot be changed).