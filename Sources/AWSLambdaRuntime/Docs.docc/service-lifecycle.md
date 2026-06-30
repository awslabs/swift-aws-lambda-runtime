# Swift Service Lifecycle integration

@Metadata {
    @PageKind(article)
    @PageColor(orange)
    @SupportedLanguage(swift)
    @PageImage(source: "lambda.png", alt: "AWS Lambda", purpose: icon)
}

Manage your Lambda runtime alongside other services using Swift Service Lifecycle.

## Overview

The runtime provides built-in support for [Swift Service Lifecycle](https://github.com/swift-server/swift-service-lifecycle), letting you manage the lifecycle of your Lambda runtime alongside other services such as database clients, HTTP clients, or any resource that needs proper initialization and cleanup.

## Example

Here is how to manage multiple services with `ServiceLifecycle`.

```swift
import AWSLambdaRuntime
import ServiceLifecycle
import PostgresNIO

@main
struct LambdaFunction {
    private func start() async throws {
        // Create a database client
        let pgClient = PostgresClient(configuration: /* your config */)

        // Create the Lambda runtime
        let lambdaRuntime = LambdaRuntime(body: self.handler)

        // Use ServiceLifecycle to manage both the database client and Lambda runtime
        let serviceGroup = ServiceGroup(
            services: [pgClient, lambdaRuntime],
            gracefulShutdownSignals: [.sigterm],
            cancellationSignals: [.sigint],
            logger: self.logger
        )

        // Start all services - this will handle initialization and cleanup
        try await serviceGroup.run()
    }

    private func handler(event: String, context: LambdaContext) async throws -> String {
        // Your Lambda function logic here
        return "Hello, World!"
    }

    static func main() async throws {
        try await LambdaFunction().start()
    }
}
```

You can see a complete working example in the [ServiceLifecycle+Postgres example](https://github.com/awslabs/swift-aws-lambda-runtime/tree/main/Examples/ServiceLifecycle%2BPostgres), which manages a PostgreSQL client alongside the Lambda runtime.

## See also

- <doc:lambda-handlers>
- <doc:background-tasks>
