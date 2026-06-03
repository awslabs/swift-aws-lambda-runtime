# Design Document

## Overview

This design introduces implicit trace ID propagation using Swift's `TaskLocal` mechanism, making the trace ID available to any code running within an invocation's structured concurrency tree. It also adds backward-compatible `_X_AMZN_TRACE_ID` environment variable setting in single-concurrency mode for legacy tooling.

Note: The AWS X-Ray SDK/Daemon entered maintenance mode on February 25, 2026. AWS recommends migrating to OpenTelemetry. This design targets OpenTelemetry instrumentation as the primary consumer of the `TaskLocal`-based propagation, while the env var fallback supports legacy tooling that still reads `_X_AMZN_TRACE_ID`.

The approach mirrors the recommendations in the cross-runtime trace propagation spec: Java uses SLF4J MDC (thread-local), Node.js uses `AsyncLocalStorage`, and Swift uses `TaskLocal` — each runtime's idiomatic context-propagation primitive.

## Architecture

The feature touches three layers:

1. **`LambdaContext` (public API)**: Adds a `@TaskLocal` static property for implicit trace ID access
2. **`Lambda.runLoop` (runtime core)**: Wraps each handler invocation in a `TaskLocal` `withValue` scope
3. **`Lambda.runLoop` (env var compat)**: Conditionally sets/clears `_X_AMZN_TRACE_ID` in single-concurrency mode

### Data Flow

```
Control Plane HTTP Response
  └─ Lambda-Runtime-Trace-Id header
       └─ InvocationMetadata.traceID (already exists)
            ├─ LambdaContext.traceID (instance property, already exists)
            ├─ LambdaContext.$currentTraceID TaskLocal (NEW)
            │    └─ Available to all code in the handler's async task tree
            └─ _X_AMZN_TRACE_ID env var (NEW, single-concurrency only)
                 └─ Available to legacy tooling / OTel auto-instrumentation via process environment
```

## Components and Interfaces

### TaskLocal Declaration on LambdaContext

```swift
@available(LambdaSwift 2.0, *)
extension LambdaContext {
    /// The trace ID for the current invocation, available via Swift's TaskLocal mechanism.
    /// This enables OpenTelemetry instrumentation and other tracing libraries to discover
    /// the trace ID without an explicit LambdaContext reference.
    /// Returns `nil` when accessed outside of a Lambda invocation scope.
    @TaskLocal
    public static var currentTraceID: String?
}
```

**Design Decisions:**
- Placed on `LambdaContext` rather than a new type, since the trace ID is already part of the context's domain
- Returns `Optional<String>` — `nil` outside invocation scope is a clear signal, no sentinel values
- Named `currentTraceID` to distinguish from the instance property `traceID` and to convey "current invocation"

### Concurrency Mode Detection

The run loop needs to know whether it's operating in single or multi-concurrency mode to decide whether to set the environment variable. Rather than re-reading `AWS_LAMBDA_MAX_CONCURRENCY` in the run loop, the concurrency mode is passed as a parameter from the caller.

```swift
@available(LambdaSwift 2.0, *)
extension Lambda {
    @inlinable
    package static func runLoop<RuntimeClient: LambdaRuntimeClientProtocol, Handler>(
        runtimeClient: RuntimeClient,
        handler: Handler,
        loggingConfiguration: LoggingConfiguration,
        logger: Logger,
        isSingleConcurrencyMode: Bool = true
    ) async throws where Handler: StreamingLambdaHandler
}
```

**Design Decisions:**
- Default value `true` preserves backward compatibility — `LambdaRuntime` (single-concurrency) doesn't need changes
- `LambdaManagedRuntime` passes `false` when `maxConcurrency > 1`
- Boolean is simpler than passing the integer concurrency value since we only need a binary decision

### Modified Run Loop (Lambda.swift)

The core change wraps the handler invocation in a `TaskLocal` scope:

```swift
// Inside the while loop, after creating requestLogger:

try await LambdaContext.$currentTraceID.withValue(invocation.metadata.traceID) {

    // Set env var only in single-concurrency mode
    if isSingleConcurrencyMode {
        setenv("_X_AMZN_TRACE_ID", invocation.metadata.traceID, 1)
    }
    defer {
        if isSingleConcurrencyMode {
            unsetenv("_X_AMZN_TRACE_ID")
        }
    }

    do {
        try await handler.handle(
            invocation.event,
            responseWriter: writer,
            context: LambdaContext(
                requestID: invocation.metadata.requestID,
                traceID: invocation.metadata.traceID,
                // ... rest unchanged
            )
        )
    } catch {
        try await writer.reportError(error)
    }
}
```

**Design Decisions:**
- `TaskLocal.withValue` is used (not `TaskLocal.withValue(operation:)` with a stored binding) to ensure the scope is tied to structured concurrency
- The env var is set inside the `withValue` scope so both mechanisms are active simultaneously
- `defer` ensures cleanup even if the handler throws
- The `setenv`/`unsetenv` calls use POSIX functions already imported in the file (`Darwin.C` / `Glibc` / `Musl`)

### LambdaManagedRuntime Changes

```swift
// In _run(), when maxConcurrency > 1:
try await LambdaRuntime.startRuntimeInterfaceClient(
    endpoint: runtimeEndpoint,
    handler: self.handler,
    eventLoop: self.eventLoop,
    loggingConfiguration: self.loggingConfiguration,
    logger: logger,
    isSingleConcurrencyMode: false  // NEW
)
```

And the `startRuntimeInterfaceClient` method passes this through to `Lambda.runLoop`.

## Error Handling

No new error types are introduced. `TaskLocal.withValue` does not throw on its own. The `setenv`/`unsetenv` calls are best-effort (their return values are ignored, matching the convention in other Lambda runtimes).

## Testing Strategy

### Unit Tests

1. **TaskLocal propagation in single-concurrency mode**
   - Verify `LambdaContext.currentTraceID` returns the correct trace ID inside a handler
   - Verify `LambdaContext.currentTraceID` returns `nil` outside a handler scope

2. **TaskLocal isolation in multi-concurrency mode**
   - Spawn multiple concurrent tasks, each with a different trace ID via `withValue`
   - Verify each task sees only its own trace ID

3. **Environment variable behavior**
   - In single-concurrency mode: verify `_X_AMZN_TRACE_ID` is set during handler execution and cleared after
   - In multi-concurrency mode: verify `_X_AMZN_TRACE_ID` is NOT set

4. **Background task propagation**
   - Verify the `TaskLocal` remains available during background work after the response is sent

### Integration Tests

- Use the existing local test server infrastructure to run a handler that reads `LambdaContext.currentTraceID` and returns it in the response, verifying it matches the trace ID sent in the invocation headers.

## Performance Considerations

- `TaskLocal` access is O(1) — it's a lookup in the task's local storage, comparable to reading a local variable
- `setenv`/`unsetenv` are syscalls but only execute in single-concurrency mode (one invocation at a time), so there's no contention
- No heap allocations beyond the `String` value already present in `InvocationMetadata.traceID`
- No new dependencies introduced

## Compatibility

- Fully backward compatible: existing `context.traceID` instance property is unchanged
- The `TaskLocal` is additive — code that doesn't use it is unaffected
- The `isSingleConcurrencyMode` parameter defaults to `true`, so `LambdaRuntime` callers don't need changes
- The env var behavior in single-concurrency mode matches what other Lambda runtimes (Python, Node.js, Java) do today for backward compatibility with legacy tooling
