# Logging

Log from your Lambda function and from the helper code it calls.

## Overview

The Swift AWS Lambda Runtime uses [swift-log](https://github.com/apple/swift-log). For
every invocation the runtime creates a request-scoped `Logger` carrying the invocation's
`requestID` and `traceID` as metadata, and passes it to your handler as
``LambdaContext/logger``:

```swift
let runtime = LambdaRuntime { (event: Request, context: LambdaContext) in
    context.logger.info("Processing request")  // includes requestID / traceID
    // ...
}
```

The log format and level are controlled by the `AWS_LAMBDA_LOG_FORMAT` (`Text` or `JSON`)
and `AWS_LAMBDA_LOG_LEVEL` / `LOG_LEVEL` environment variables.

## Logging without passing the logger around

Threading `context.logger` through every function your handler calls is tedious. Instead,
the runtime binds the request logger as the task-local
[`Logger.current`](https://github.com/apple/swift-log) for the duration of the handler
call. Code anywhere in the handler's call tree can read `Logger.current` and inherit the
invocation's metadata, without a `LambdaContext` or `Logger` parameter:

```swift
import Logging

func validate(_ event: Request) {
    // No logger parameter — reads the task-local logger bound by the runtime.
    Logger.current.debug("Validating request")
}

let runtime = LambdaRuntime { (event: Request, context: LambdaContext) in
    validate(event)  // its log lines still carry this invocation's requestID / traceID
    // ...
}
```

Inside the handler itself, `context.logger` and `Logger.current` are equivalent. Use
whichever reads better; `context.logger` is more explicit at the call site.

### Binding a logger yourself

`Logger.current` is bound with the free function `withLogger(_:)` from swift-log. The
runtime does this for you per invocation, but you can also bind a logger at application
startup so it is in scope before and around `run()`. This is useful when combining Lambda with
other services, such as the [ServiceLifecycle](https://github.com/swift-server/swift-service-lifecycle):

```swift
let logger = Logger(label: "my-function")
try await withLogger(logger) { _ in
    let runtime = LambdaRuntime(body: handler)
    try await runtime.run()
}
```

## Note

Task-local values propagate through structured concurrency (`async let`,
`withTaskGroup`, child `Task {}`) but are **not** inherited by `Task.detached`.
You must capture the logger explicitly across a detached boundary.

## Topics

### Related types

- ``LambdaContext``
- ``LoggingConfiguration``
