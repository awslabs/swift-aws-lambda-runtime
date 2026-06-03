# Implementation Plan

- [ ] 1. Add `@TaskLocal` property to `LambdaContext`
  - In `Sources/AWSLambdaRuntime/LambdaContext.swift`, add a `@TaskLocal` static property `currentTraceID` of type `String?` to `LambdaContext` via an extension
  - Add documentation comment explaining the property returns the trace ID for the current invocation, or `nil` outside an invocation scope. Note that this is intended for use by OpenTelemetry instrumentation and tracing middleware.
  - _Requirements: 1.1, 1.3, 4.1, 4.2_

- [ ] 2. Add `isSingleConcurrencyMode` parameter to `Lambda.runLoop`
  - In `Sources/AWSLambdaRuntime/Lambda.swift`, add a `isSingleConcurrencyMode: Bool = true` parameter to both `runLoop` overloads (the current one and the deprecated one)
  - The deprecated overload should forward the parameter to the current overload
  - _Requirements: 2.1, 2.3_

- [ ] 3. Wrap handler invocation in `TaskLocal.withValue` scope in `Lambda.runLoop`
  - In `Sources/AWSLambdaRuntime/Lambda.swift`, inside the `while !Task.isCancelled` loop, wrap the handler invocation (from `handler.handle(...)` through the catch block) in `LambdaContext.$currentTraceID.withValue(invocation.metadata.traceID) { ... }`
  - Inside the `withValue` scope, conditionally call `setenv("_X_AMZN_TRACE_ID", invocation.metadata.traceID, 1)` when `isSingleConcurrencyMode` is `true`
  - Add a `defer` block that calls `unsetenv("_X_AMZN_TRACE_ID")` when `isSingleConcurrencyMode` is `true`
  - _Requirements: 1.1, 1.2, 2.1, 2.2, 2.3, 3.1, 3.2, 3.3_

- [ ] 4. Add `isSingleConcurrencyMode` parameter to `LambdaRuntime.startRuntimeInterfaceClient`
  - In `Sources/AWSLambdaRuntime/Runtime/LambdaRuntime.swift`, add `isSingleConcurrencyMode: Bool = true` parameter to the `startRuntimeInterfaceClient` static method
  - Pass the parameter through to `Lambda.runLoop`
  - _Requirements: 2.1, 2.3_

- [ ] 5. Pass `isSingleConcurrencyMode: false` from `LambdaManagedRuntime` when concurrency > 1
  - In `Sources/AWSLambdaRuntime/ManagedRuntime/LambdaManagedRuntime.swift`, in the `_run()` method, when `maxConcurrency > 1`, pass `isSingleConcurrencyMode: false` to `LambdaRuntime.startRuntimeInterfaceClient`
  - The single-concurrency path (`maxConcurrency <= 1`) should pass `isSingleConcurrencyMode: true` (or rely on the default)
  - _Requirements: 2.1, 2.3_

- [ ] 6. Write unit tests for `TaskLocal` trace ID propagation
  - Create or extend test file in `Tests/AWSLambdaRuntimeTests/` to test `LambdaContext.currentTraceID`
  - Test that `LambdaContext.currentTraceID` returns `nil` outside an invocation scope
  - Test that `LambdaContext.$currentTraceID.withValue("test-trace-id") { ... }` makes the value accessible inside the closure
  - Test that concurrent tasks with different trace IDs via `withValue` each see their own value (no cross-contamination)
  - _Requirements: 1.2, 1.4_

- [ ] 7. Write unit tests for environment variable behavior
  - Test that in single-concurrency mode, `_X_AMZN_TRACE_ID` is set during handler execution (use the local test server or mock runtime client)
  - Test that in single-concurrency mode, `_X_AMZN_TRACE_ID` is cleared after handler execution
  - Test that in multi-concurrency mode, `_X_AMZN_TRACE_ID` is NOT set during handler execution
  - _Requirements: 2.1, 2.2, 2.3_

- [ ] 8. Update documentation
  - Update `Sources/AWSLambdaRuntime/Docs.docc/` if there is existing documentation about tracing or context to mention `LambdaContext.currentTraceID`
  - Add a brief note in the managed instances documentation (`Sources/AWSLambdaRuntime/Docs.docc/managed-instances.md`) about trace ID propagation in multi-concurrency mode
  - _Requirements: 1.1, 4.1_
