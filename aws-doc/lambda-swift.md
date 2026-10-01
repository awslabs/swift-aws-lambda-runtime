# Building Lambda functions with Swift

Because Swift compiles to native code, you don't need a dedicated runtime to run Swift code on Lambda. Instead, use the Swift runtime client to build your project locally, and then deploy it to Lambda using an OS-only runtime. When you use an OS-only runtime, Lambda automatically keeps the operating system up to date with the latest patches.

## Tools and libraries for Swift

- **AWS SDK for Swift**: The [AWS SDK for Swift](https://github.com/awslabs/aws-sdk-swift) provides Swift APIs to interact with Amazon Web Services infrastructure services.
- **Swift runtime client for Lambda**: The [Swift runtime client](https://github.com/awslabs/swift-aws-lambda-runtime) makes it easy to run Lambda functions written in Swift.
- **Swift AWS Lambda Events**: This [library](https://github.com/awslabs/swift-aws-lambda-events) provides type definitions for common event source integrations.
- **Swift OpenAPI Lambda**: This [library](https://github.com/awslabs/swift-openapi-lambda) provides an AWS Lambda transport for Swift OpenAPI, allowing you to expose OpenAPI-based services as Lambda functions.

## Sample Lambda applications for Swift

- [Simple Lambda function](https://github.com/awslabs/swift-aws-lambda-runtime/blob/main/Examples/HelloJSON): A Swift function that shows how to process basic JSON events.
- [Lambda function with background tasks](https://github.com/awslabs/swift-aws-lambda-runtime/tree/main/Examples/BackgroundTasks): A Swift function that shows how to perform background processing after sending a response.
- [Lambda function with streaming responses](https://github.com/awslabs/swift-aws-lambda-runtime/tree/main/Examples/Streaming%2BAPIGateway): A Swift function that streams responses back to the client.
- [Lambda HTTP events](https://github.com/awslabs/swift-aws-lambda-runtime/tree/main/Examples/APIGatewayV2): A Swift function that handles API Gateway HTTP events.
- [Lambda function with Service Lifecycle](https://github.com/awslabs/swift-aws-lambda-runtime/tree/main/Examples/ServiceLifecycle%2BPostgres): A Swift project that initializes shared resources using Swift Service Lifecycle before creating the Lambda function.

## Topics

- [Define Lambda function handlers in Swift](swift-handler.md)
- [Using the Lambda context object to retrieve Swift function information](swift-context.md)
- [Processing HTTP events with Swift](swift-http-events.md)
- [Deploy Swift Lambda functions with .zip file archives](swift-package.md)
- [Working with layers for Swift Lambda functions](swift-layers.md)
- [Log and monitor Swift Lambda functions](swift-logging.md)

