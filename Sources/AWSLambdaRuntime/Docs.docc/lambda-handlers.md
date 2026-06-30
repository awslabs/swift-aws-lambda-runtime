# Writing your Lambda function

@Metadata {
    @PageKind(article)
    @PageColor(orange)
    @SupportedLanguage(swift)
    @PageImage(source: "lambda.png", alt: "AWS Lambda", purpose: icon)
}

Write Lambda function handlers, from a simple JSON request/response to integrating with AWS services.

## Overview

The Swift AWS Lambda Runtime provides a layered API that scales with your needs. You can start with a simple closure that receives a `Decodable` event and returns an `Encodable` response, then move to streaming responses, background work, or full lifecycle management as your function grows.

This article covers the two most common patterns: handling JSON, and reacting to events from other AWS services. For the more advanced patterns, see <doc:streaming-responses>, <doc:background-tasks>, and <doc:service-lifecycle>.

Each pattern links to a complete, runnable example in the [Examples](https://github.com/awslabs/swift-aws-lambda-runtime/tree/main/Examples) directory.

## Receive and respond with JSON objects

Typically, your Lambda function receives an input expressed as JSON and responds with JSON. The runtime automatically decodes and encodes JSON when your handler accepts a `Decodable` event and returns an `Encodable` response.

Here is a minimal function that accepts a JSON object as input and responds with another JSON object.

```swift
import AWSLambdaRuntime

// the data structure to represent the input parameter
struct HelloRequest: Decodable {
    let name: String
    let age: Int
}

// the data structure to represent the output response
struct HelloResponse: Encodable {
    let greetings: String
}

// the Lambda runtime
let runtime = LambdaRuntime {
    (event: HelloRequest, context: LambdaContext) in

    HelloResponse(
        greetings: "Hello \(event.name). You look \(event.age > 30 ? "younger" : "older") than your age."
    )
}

// start the loop
try await runtime.run()
```

You can learn how to deploy and invoke this function in the [Hello JSON example](https://github.com/awslabs/swift-aws-lambda-runtime/tree/main/Examples/HelloJSON).

## Integrate with AWS services

Most Lambda functions are triggered by events originating in other AWS services such as Amazon SNS, Amazon SQS, or AWS API Gateway.

The [Swift AWS Lambda Events](https://github.com/awslabs/swift-aws-lambda-events) package includes an `AWSLambdaEvents` module that provides implementations for most common AWS event types, further simplifying writing Lambda functions.

> Note: This library has no dependency on the AWS Lambda Events library. It is safe to use AWS Lambda Events v1.x with this runtime v2.

To use these event types, add `swift-aws-lambda-events` as a dependency in your `Package.swift` and add the `AWSLambdaEvents` product to your target.

```swift
let package = Package(
    name: "MyLambda",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/awslabs/swift-aws-lambda-runtime.git", from: "2.0.0"),
        .package(url: "https://github.com/awslabs/swift-aws-lambda-events.git", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "MyLambda",
            dependencies: [
                .product(name: "AWSLambdaRuntime", package: "swift-aws-lambda-runtime"),
                .product(name: "AWSLambdaEvents", package: "swift-aws-lambda-events"),
            ]
        )
    ]
)
```

Or add it from the command line:

```bash
swift package add-dependency https://github.com/awslabs/swift-aws-lambda-events.git --from 1.0.0
swift package add-target-dependency AWSLambdaEvents MyLambda --package swift-aws-lambda-events
```

Here is an example Lambda function invoked when AWS API Gateway receives an HTTP request.

```swift
import AWSLambdaEvents
import AWSLambdaRuntime

let runtime = LambdaRuntime {
    (event: APIGatewayV2Request, context: LambdaContext) -> APIGatewayV2Response in

    APIGatewayV2Response(statusCode: .ok, body: "Hello World!")
}

try await runtime.run()
```

You can learn how to deploy and invoke this function in the [API Gateway example](https://github.com/awslabs/swift-aws-lambda-runtime/tree/main/Examples/APIGatewayV2).

## See Also

- <doc:streaming-responses>
- <doc:background-tasks>
- <doc:service-lifecycle>
- <doc:managed-instances>
