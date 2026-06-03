# Requirements Document

## Introduction

This feature adds proper X-Ray Trace ID propagation for multi-concurrent Lambda environments (Managed Instances / "Elevator"). Today, the Swift Lambda runtime extracts the `Lambda-Runtime-Trace-Id` header per invocation and passes it through `LambdaContext.traceID`, but it does not provide an implicit propagation mechanism. Downstream libraries (e.g., OpenTelemetry instrumentation or HTTP client middleware) have no way to discover the current invocation's trace ID without an explicit `LambdaContext` reference. In multi-concurrent mode (`AWS_LAMBDA_MAX_CONCURRENCY > 1`), multiple invocations run simultaneously in the same process, making process-level environment variables unsuitable for trace propagation.

Note: The AWS X-Ray SDK/Daemon entered maintenance mode on February 25, 2026. AWS recommends migrating to OpenTelemetry for instrumentation. This design targets OpenTelemetry as the primary consumer of implicit trace ID propagation, while maintaining the `_X_AMZN_TRACE_ID` environment variable in single-concurrency mode for backward compatibility with legacy tooling.

The solution uses Swift's `TaskLocal` to store the trace ID in the current task's scope, making it implicitly available to all code running within an invocation's async call tree. In single-concurrency mode, the runtime additionally sets the `_X_AMZN_TRACE_ID` environment variable for backward compatibility with legacy tooling that reads it.

## Requirements

### Requirement 1

**User Story:** As a library author building OpenTelemetry or tracing middleware for Swift Lambda functions, I want to implicitly access the current invocation's trace ID from anywhere in the async call tree, so that I can auto-inject trace context headers on outbound HTTP calls without requiring an explicit `LambdaContext` reference.

#### Acceptance Criteria

1. WHEN a Lambda invocation is being handled THEN the system SHALL make the X-Ray Trace ID available via a `TaskLocal` property accessible as `LambdaContext.currentTraceID`
2. WHEN code running inside the handler's async call tree accesses `LambdaContext.currentTraceID` THEN it SHALL return the trace ID for the current invocation
3. WHEN code running outside any invocation scope accesses `LambdaContext.currentTraceID` THEN it SHALL return `nil`
4. WHEN multiple invocations run concurrently THEN each invocation's `TaskLocal` SHALL contain its own trace ID without cross-contamination

### Requirement 2

**User Story:** As a Lambda function developer using the traditional single-concurrency mode, I want the runtime to set the `_X_AMZN_TRACE_ID` environment variable per invocation, so that legacy tooling and OpenTelemetry auto-instrumentation that reads this variable continues to work without code changes.

#### Acceptance Criteria

1. WHEN `AWS_LAMBDA_MAX_CONCURRENCY` is 1 or unset THEN the runtime SHALL set the `_X_AMZN_TRACE_ID` process environment variable to the current invocation's trace ID before calling the handler
2. WHEN the invocation completes THEN the runtime SHALL clear the `_X_AMZN_TRACE_ID` environment variable
3. WHEN `AWS_LAMBDA_MAX_CONCURRENCY` is greater than 1 THEN the runtime SHALL NOT set the `_X_AMZN_TRACE_ID` environment variable (to avoid cross-invocation contamination)

### Requirement 3

**User Story:** As a Lambda function developer, I want the `TaskLocal`-based trace ID propagation to work transparently with all handler protocols (`StreamingLambdaHandler`, `LambdaHandler`, `LambdaWithBackgroundProcessingHandler`), so that I don't need to change my handler code.

#### Acceptance Criteria

1. WHEN the runtime invokes any handler type THEN the trace ID `TaskLocal` SHALL be set before the handler's `handle` function is called
2. WHEN background work executes after the response is sent (via `LambdaWithBackgroundProcessingHandler`) THEN the `TaskLocal` trace ID SHALL remain available during background execution
3. WHEN the handler function returns or throws THEN the `TaskLocal` scope SHALL end naturally via structured concurrency

### Requirement 4

**User Story:** As a Lambda function developer, I want a public API to read the current trace ID for manual propagation scenarios, so that I can pass it to libraries that don't automatically read the `TaskLocal`.

#### Acceptance Criteria

1. WHEN a developer accesses `LambdaContext.currentTraceID` THEN it SHALL return an `Optional<String>` containing the trace ID or `nil` if not in an invocation scope
2. WHEN a developer accesses `context.traceID` on a `LambdaContext` instance THEN it SHALL continue to work as before (no breaking changes)

### Requirement 5

**User Story:** As a maintainer of the Swift Lambda runtime, I want the trace propagation mechanism to have minimal performance overhead, so that it does not impact cold start times or invocation latency.

#### Acceptance Criteria

1. WHEN the `TaskLocal` is set per invocation THEN the overhead SHALL be negligible (sub-microsecond, comparable to a dictionary lookup)
2. WHEN running in single-concurrency mode THEN the `setenv`/`unsetenv` calls SHALL add no measurable latency to invocation processing
3. WHEN the feature is compiled THEN it SHALL NOT introduce any new external dependencies beyond what the runtime already uses
