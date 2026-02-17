# Lambda Managed Instances

@Metadata {
    @PageKind(article)
    @PageColor(orange)
    @SupportedLanguage(swift)
    @PageImage(source: "lambda.png", alt: "AWS Lambda", purpose: icon)
}

Deploy Swift Lambda functions on Amazon EC2 instances with concurrent execution support

## Overview

Lambda Managed Instances enables you to run Lambda functions on your current-generation Amazon EC2 instances while maintaining serverless simplicity. AWS handles all infrastructure management tasks including instance lifecycle, OS and runtime patching, routing, load balancing, and auto-scaling, while you benefit from EC2 flexibility and cost optimization.

The key difference from traditional Lambda is concurrent execution support—multiple invocations can run simultaneously within the same execution environment on the same EC2 host.

## When to Use Lambda Managed Instances

Lambda Managed Instances are ideal for:

- **Sustained workloads** where cost optimization through EC2 pricing models provides better economics than traditional Lambda
- **Specialized compute requirements** needing specific EC2 instance types such as Graviton4 or network-optimized instances
- **High-throughput scenarios** where concurrent execution on the same host improves performance and resource utilization
- **Workloads requiring EC2 flexibility** while maintaining serverless operational simplicity

## Code Changes Required

Migrating existing Lambda functions to Lambda Managed Instances requires two simple changes:

### 1. Use `LambdaManagedRuntime` Instead of `LambdaRuntime`

Replace your standard `LambdaRuntime` initialization with `LambdaManagedRuntime`:

```swift
import AWSLambdaRuntime

// Before (standard Lambda)
let runtime = LambdaRuntime {
    (event: HelloRequest, context: LambdaContext) in
    HelloResponse(greetings: "Hello \(event.name)!")
}

// After (Lambda Managed Instances)
let runtime = LambdaManagedRuntime {
    (event: HelloRequest, context: LambdaContext) in
    HelloResponse(greetings: "Hello \(event.name)!")
}

try await runtime.run()
```

### 2. Ensure Handlers Conform to `Sendable`

Because Lambda Managed Instances support concurrent invocations, your handler functions and structs must conform to the `Sendable` protocol to ensure thread safety:

```swift
import AWSLambdaRuntime

// Handler struct must explicitly conform to Sendable
struct MyHandler: LambdaWithBackgroundProcessingHandler, Sendable {
    typealias Event = MyRequest
    typealias Output = MyResponse
    
    func handle(
        _ event: Event,
        outputWriter: some LambdaResponseWriter<Output>,
        context: LambdaContext
    ) async throws {
        try await outputWriter.write(MyResponse(message: "Processed"))
    }
}

// Use LambdaCodableAdapter to pass the handler to LambdaManagedRuntime
let adapter = LambdaCodableAdapter(handler: MyHandler())
let runtime = LambdaManagedRuntime(handler: adapter)
try await runtime.run()
```

For simple data structures, the Swift compiler automatically infers `Sendable` conformance, but explicitly declaring it is recommended for clarity and safety.

## How It Works

The runtime automatically detects the configured concurrency level through the `AWS_LAMBDA_MAX_CONCURRENCY` environment variable and launches the appropriate number of Runtime Interface Clients (RICs) to handle concurrent requests efficiently.

When `AWS_LAMBDA_MAX_CONCURRENCY` is 1 or unset, the runtime maintains single-threaded behavior for optimal performance on traditional Lambda deployments, ensuring backward compatibility.

The managed instances support is implemented behind a Swift package trait (`ManagedRuntimeSupport`) that's enabled by default. If you're concerned about binary size and don't need managed instances support, you can disable this specific trait in your `Package.swift`:

```swift
dependencies: [
    .package(
        url: "https://github.com/awslabs/swift-aws-lambda-runtime.git",
        from: "2.0.0",
        traits: [
            // Keep other default traits but exclude ManagedRuntimeSupport
            "FoundationJSONSupport",
            "ServiceLifecycleSupport",
            "LocalServerSupport"
        ]
    ),
],
targets: [
    .executableTarget(
        name: "MyLambda",
        dependencies: [
            .product(name: "AWSLambdaRuntime", package: "swift-aws-lambda-runtime"),
        ]
    ),
]
```

## Prerequisites

Before deploying to Lambda Managed Instances:

1. Create a [Lambda Managed Instances capacity provider](https://docs.aws.amazon.com/lambda/latest/dg/lambda-managed-instances-capacity-providers.html) in your AWS account
2. Configure your deployment to reference the capacity provider ARN

## Example Functions

The Swift AWS Lambda Runtime includes three comprehensive examples demonstrating Lambda Managed Instances capabilities:

- **HelloJSON**: JSON input/output with structured data types and concurrent execution
- **Streaming**: Response streaming with concurrent invocation handling
- **BackgroundTasks**: Long-running background processing after response with concurrency support

See the [ManagedInstances example directory](https://github.com/awslabs/swift-aws-lambda-runtime/tree/main/Examples/ManagedInstances) for complete deployment instructions using AWS SAM.

## Additional Resources

- [AWS Lambda Managed Instances Documentation](https://docs.aws.amazon.com/lambda/latest/dg/lambda-managed-instances.html)
- [Execution Environment Guide](https://docs.aws.amazon.com/lambda/latest/dg/lambda-managed-instances-execution-environment.html)
- [Capacity Provider Configuration](https://docs.aws.amazon.com/lambda/latest/dg/lambda-managed-instances-capacity-providers.html)
