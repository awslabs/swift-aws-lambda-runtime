# Processing HTTP events with Swift

Amazon API Gateway APIs, Application Load Balancers, and Lambda function URLs can send HTTP events to Lambda. You can use the [Swift AWS Lambda Events](https://github.com/awslabs/swift-aws-lambda-events) package to process events from these sources.

## Example — Handle API Gateway V2 proxy request

Note the following:

- `import AWSLambdaEvents`: The `AWSLambdaEvents` package includes many Lambda event types. Add it to your `Package.swift` as a dependency of your target.
- `APIGatewayV2Request` and `APIGatewayV2Response`: These are the pre-defined request and response types for API Gateway HTTP API (V2) events.

```swift
import AWSLambdaRuntime
import AWSLambdaEvents

let runtime = LambdaRuntime {
    (event: APIGatewayV2Request, context: LambdaContext) -> APIGatewayV2Response in

    return APIGatewayV2Response(
        statusCode: .ok,
        body: "Hello AWS Lambda HTTP request"
    )
}

try await runtime.run()
```

## Example — Handle API Gateway V1 (REST API) proxy request

If you use API Gateway REST API (V1), use the `APIGatewayRequest` and `APIGatewayResponse` types instead:

```swift
import AWSLambdaRuntime
import AWSLambdaEvents

let runtime = LambdaRuntime {
    (event: APIGatewayRequest, context: LambdaContext) -> APIGatewayResponse in

    return APIGatewayResponse(
        statusCode: .ok,
        headers: ["content-type": "text/html"],
        body: "Hello AWS Lambda HTTP request"
    )
}

try await runtime.run()
```

## Example — Handle Lambda Function URL request

Lambda function URLs use the same event format as API Gateway HTTP API (V2). You can use `FunctionURLRequest` and `FunctionURLResponse` types, which are equivalent to `APIGatewayV2Request` and `APIGatewayV2Response`:

```swift
import AWSLambdaRuntime
import AWSLambdaEvents

let runtime = LambdaRuntime {
    (event: FunctionURLRequest, context: LambdaContext) -> FunctionURLResponse in

    return FunctionURLResponse(
        statusCode: .ok,
        headers: ["content-type": "application/json"],
        body: #"{"message": "Hello from Lambda Function URL"}"#
    )
}

try await runtime.run()
```

## Example — Using the protocol-based approach

For larger applications, you can use the `LambdaHandler` protocol:

```swift
import AWSLambdaRuntime
import AWSLambdaEvents

struct APIGatewayLambda: LambdaHandler {
    func handle(
        _ request: APIGatewayV2Request,
        context: LambdaContext
    ) async throws -> APIGatewayV2Response {
        context.logger.debug("HTTP Method: \(request.context.http.method.rawValue)")
        context.logger.debug("Path: \(request.rawPath)")

        return APIGatewayV2Response(
            statusCode: .ok,
            body: #"{"message": "Hello, World!"}"#
        )
    }
}

let handler = APIGatewayLambda()
let runtime = LambdaRuntime(handler: LambdaCodableAdapter(handler: LambdaHandlerAdapter(handler: handler)))
try await runtime.run()
```

## Adding the AWSLambdaEvents dependency

To use the pre-defined event types, add the `swift-aws-lambda-events` package to your `Package.swift`:

```swift
// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "MyHTTPFunction",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/awslabs/swift-aws-lambda-runtime.git", from: "3.0.0"),
        .package(url: "https://github.com/awslabs/swift-aws-lambda-events.git", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "MyHTTPFunction",
            dependencies: [
                .product(name: "AWSLambdaRuntime", package: "swift-aws-lambda-runtime"),
                .product(name: "AWSLambdaEvents", package: "swift-aws-lambda-events"),
            ]
        )
    ]
)
```

## Sample HTTP Lambda events for Swift

- [API Gateway example](https://github.com/awslabs/swift-aws-lambda-runtime/tree/main/Examples/APIGatewayV2): A Swift function that handles API Gateway HTTP events.
- [Lambda function URL example](https://github.com/awslabs/swift-aws-lambda-runtime/tree/main/Examples/HelloJSON): A Swift function that handles Lambda function URL events.
- [Streaming response example](https://github.com/awslabs/swift-aws-lambda-runtime/tree/main/Examples/Streaming%2BAPIGateway): A Swift function that streams HTTP responses back to the client.
