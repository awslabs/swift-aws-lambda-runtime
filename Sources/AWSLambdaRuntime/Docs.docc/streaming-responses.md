# Streaming responses

@Metadata {
    @PageKind(article)
    @PageColor(orange)
    @SupportedLanguage(swift)
    @PageImage(source: "lambda.png", alt: "AWS Lambda", purpose: icon)
}

Stream response payloads back to clients as they become available.

## Overview

You can configure your Lambda function to stream response payloads back to clients. Response streaming can benefit latency-sensitive applications by improving time to first byte (TTFB) performance. You can send partial responses back to the client as they become available.

Response streaming also lets you return larger payloads. Streamed responses have a soft limit of 200 MB, compared to the 6 MB limit for buffered responses. Because the function does not need to hold the entire response in memory, you can also reduce the amount of memory you configure for your function.

Streaming responses incur a cost. For more information, see [AWS Lambda Pricing](https://aws.amazon.com/lambda/pricing/).

You can stream responses through [Lambda function URLs](https://docs.aws.amazon.com/lambda/latest/dg/urls-configuration.html), the AWS SDK, or the Lambda [InvokeWithResponseStream](https://docs.aws.amazon.com/lambda/latest/dg/API_InvokeWithResponseStream.html) API.

## Simple streaming

Here is a minimal function that streams 10 numbers, one per second.

```swift
import AWSLambdaRuntime
import NIOCore

struct SendNumbersWithPause: StreamingLambdaHandler {
    func handle(
        _ event: ByteBuffer,
        responseWriter: some LambdaResponseStreamWriter,
        context: LambdaContext
    ) async throws {
        for i in 1...10 {
            // Send partial data
            try await responseWriter.write(ByteBuffer(string: "\(i)\n"))
            // Perform some long asynchronous work
            try await Task.sleep(for: .milliseconds(1000))
        }
        // All data has been sent. Close off the response stream.
        try await responseWriter.finish()
    }
}

let runtime = LambdaRuntime(handler: SendNumbersWithPause())
try await runtime.run()
```

## Streaming with HTTP status code and headers

When streaming responses, you can set the HTTP status code and headers before sending the body. This is useful when your function is invoked through API Gateway or a Lambda function URL, where you want to control the HTTP response metadata.

```swift
import AWSLambdaRuntime
import NIOCore

struct StreamingWithHeaders: StreamingLambdaHandler {
    func handle(
        _ event: ByteBuffer,
        responseWriter: some LambdaResponseStreamWriter,
        context: LambdaContext
    ) async throws {
        // Set HTTP status code and headers before streaming the body
        let response = StreamingLambdaStatusAndHeadersResponse(
            statusCode: 200,
            headers: [
                "Content-Type": "text/plain",
                "Cache-Control": "no-cache",
            ]
        )
        try await responseWriter.writeStatusAndHeaders(response)

        // Now stream the response body
        for i in 1...5 {
            try await responseWriter.write(ByteBuffer(string: "Chunk \(i)\n"))
            try await Task.sleep(for: .milliseconds(500))
        }

        try await responseWriter.finish()
    }
}

let runtime = LambdaRuntime(handler: StreamingWithHeaders())
try await runtime.run()
```

The `writeStatusAndHeaders` method lets you set the HTTP status code, add custom headers for content type, caching, or CORS, and control the response metadata before streaming begins, while staying compatible with API Gateway and Lambda function URLs.

You can learn how to deploy and invoke this function in the [Streaming example](https://github.com/awslabs/swift-aws-lambda-runtime/tree/main/Examples/Streaming+APIGateway).

## Streaming with JSON input

The runtime also provides an interface that combines JSON input decoding with response streaming. This is ideal when you want to receive a strongly typed JSON event while keeping the ability to stream responses and run background work.

```swift
import AWSLambdaRuntime
import NIOCore

// Define your input event structure
struct StreamingRequest: Decodable {
    let count: Int
    let message: String
    let delayMs: Int?
}

// Use the streaming handler with JSON decoding
let runtime = LambdaRuntime { (event: StreamingRequest, responseWriter, context: LambdaContext) in
    context.logger.info("Received request to send \(event.count) messages")

    // Stream the messages
    for i in 1...event.count {
        let response = "Message \(i)/\(event.count): \(event.message)\n"
        try await responseWriter.write(ByteBuffer(string: response))

        // Optional delay between messages
        if let delay = event.delayMs, delay > 0 {
            try await Task.sleep(for: .milliseconds(delay))
        }
    }

    // Finish the stream
    try await responseWriter.finish()

    // Optional: Execute background work after response is sent
    context.logger.info("Background work: processing completed")
}

try await runtime.run()
```

This interface gives you type-safe JSON decoding, full control over streaming, the ability to run background work after the stream finishes, and the same closure-based pattern as regular handlers.

You can learn how to deploy and invoke this function in the [Streaming from event example](https://github.com/awslabs/swift-aws-lambda-runtime/tree/main/Examples/Streaming+Codable).

## See also

- <doc:background-tasks>
- <doc:lambda-handlers>
