## [core] Implement Trace ID Propagation for Multi-Concurrent Environments

The Swift AWS Lambda Runtime currently receives the trace ID from the Lambda Runtime API via the `Lambda-Runtime-Trace-Id` header and stores it in `LambdaContext.traceID`. However, there's no implicit propagation mechanism — downstream code (OpenTelemetry instrumentation, HTTP client middleware) can't discover the current invocation's trace ID without an explicit `LambdaContext` reference.

According to the [AWS Lambda Runtime API documentation](https://docs.aws.amazon.com/lambda/latest/dg/runtimes-api.html), the runtime should also set the `_X_AMZN_TRACE_ID` environment variable. This is missing from the Swift runtime.

> **Note:** The AWS X-Ray SDK/Daemon entered maintenance mode on February 25, 2026. AWS recommends migrating to [OpenTelemetry](https://docs.aws.amazon.com/xray/latest/devguide/xray-otel-migration.html). The `TaskLocal`-based propagation proposed here is the forward-looking mechanism for OpenTelemetry integration. The `_X_AMZN_TRACE_ID` environment variable is maintained for backward compatibility with legacy tooling only.

### Current Behavior

- The runtime receives the `Lambda-Runtime-Trace-Id` header from the Lambda Runtime API
- The trace ID is stored in `LambdaContext.traceID`
- The `_X_AMZN_TRACE_ID` environment variable is **not** set
- No implicit propagation mechanism exists for downstream libraries

### Expected Behavior

- The runtime receives the `Lambda-Runtime-Trace-Id` header
- The trace ID is stored in `LambdaContext.traceID` (unchanged)
- A `@TaskLocal` makes the trace ID implicitly available to all code in the handler's async task tree
- In single-concurrency mode only, the `_X_AMZN_TRACE_ID` environment variable is set per invocation and cleared after

### Implementation Considerations

#### Standard Lambda Functions (single concurrency)

Setting the environment variable with `setenv()` is straightforward since only one invocation runs at a time. The `TaskLocal` is also set for consistency.

#### Lambda Managed Instances (multi-concurrency)

Multiple concurrent invocations share the same process. Environment variables are process-global, so setting `_X_AMZN_TRACE_ID` would cause trace ID conflicts between concurrent invocations. In this mode, the runtime must **skip** the env var entirely and rely solely on the `TaskLocal`.

The runtime detects the mode via `AWS_LAMBDA_MAX_CONCURRENCY` (already read by `LambdaManagedRuntime`).

### How Other Runtimes Handle This

- **Python:** Uses `os.environ['_X_AMZN_TRACE_ID']` — safe because Python's multi-concurrency model uses separate processes with isolated `os.environ` ([ref](https://github.com/aws/aws-lambda-python-runtime-interface-client))
- **Java:** Uses SLF4J MDC (thread-local map) to avoid `SystemProperty` conflicts across threads ([ref](https://github.com/aws/aws-lambda-java-libs))
- **Node.js:** Uses `AsyncLocalStorage` to bind trace ID to the current async call chain ([ref](https://github.com/aws/aws-lambda-nodejs-runtime-interface-client))

### Solution: TaskLocal + Conditional Environment Variable

Swift's `TaskLocal` is the direct equivalent of Java's MDC and Node.js's `AsyncLocalStorage`. It isolates values to the current structured concurrency tree.

#### 1. Define TaskLocal on LambdaContext

```swift
@available(LambdaSwift 2.0, *)
extension LambdaContext {
    @TaskLocal
    public static var currentTraceID: String?
}
```

#### 2. Wrap Handler Invocation in TaskLocal Scope

In `Sources/AWSLambdaRuntime/Lambda.swift`, inside `Lambda.runLoop`:

```swift
try await LambdaContext.$currentTraceID.withValue(invocation.metadata.traceID) {
    if isSingleConcurrencyMode {
        setenv("_X_AMZN_TRACE_ID", invocation.metadata.traceID, 1)
    }
    defer {
        if isSingleConcurrencyMode {
            unsetenv("_X_AMZN_TRACE_ID")
        }
    }

    try await handler.handle(invocation.event, responseWriter: writer, context: context)
}
```

#### 3. Thread Concurrency Mode Through the Call Chain

Add `isSingleConcurrencyMode: Bool = true` parameter to:
- `Lambda.runLoop` (default `true` for backward compat)
- `LambdaRuntime.startRuntimeInterfaceClient`

`LambdaManagedRuntime` passes `false` when `maxConcurrency > 1`.

### Files to Modify

- **`Sources/AWSLambdaRuntime/LambdaContext.swift`** — Add `@TaskLocal public static var currentTraceID: String?`
- **`Sources/AWSLambdaRuntime/Lambda.swift`** — Wrap handler call in `withValue` scope, add `isSingleConcurrencyMode` parameter, conditionally set/clear env var
- **`Sources/AWSLambdaRuntime/Runtime/LambdaRuntime.swift`** — Add `isSingleConcurrencyMode` parameter to `startRuntimeInterfaceClient`, pass through to `Lambda.runLoop`
- **`Sources/AWSLambdaRuntime/ManagedRuntime/LambdaManagedRuntime.swift`** — Pass `isSingleConcurrencyMode: false` when `maxConcurrency > 1`

### Testing Requirements

- [ ] `LambdaContext.currentTraceID` returns `nil` outside invocation scope
- [ ] `LambdaContext.currentTraceID` returns correct value inside handler
- [ ] Concurrent tasks with different trace IDs see their own values (no cross-contamination)
- [ ] Single-concurrency mode: `_X_AMZN_TRACE_ID` is set during handler execution and cleared after
- [ ] Multi-concurrency mode: `_X_AMZN_TRACE_ID` is NOT set
- [ ] TaskLocal remains available during background work after response is sent

### References

- [AWS Lambda Runtime API Documentation](https://docs.aws.amazon.com/lambda/latest/dg/runtimes-api.html)
- [X-Ray Tracing Header Documentation](https://docs.aws.amazon.com/xray/latest/devguide/xray-concepts.html#xray-concepts-tracingheader)
- [Migrating from X-Ray to OpenTelemetry](https://docs.aws.amazon.com/xray/latest/devguide/xray-otel-migration.html)
- [Swift TaskLocal Documentation](https://developer.apple.com/documentation/swift/tasklocal)
- Design and implementation plan: `.kiro/specs/xray-trace-id-propagation/`
