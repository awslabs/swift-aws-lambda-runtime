# Background tasks

@Metadata {
    @PageKind(article)
    @PageColor(orange)
    @SupportedLanguage(swift)
    @PageImage(source: "lambda.png", alt: "AWS Lambda", purpose: icon)
}

Run code after returning a response, without adding to response latency.

## Overview

Background tasks let code run after the main response has been returned, enabling additional processing without affecting response latency. This is ideal for logging, data updates, or notifications that can be deferred.

The approach leverages Lambda's response streaming feature to balance real-time responsiveness with extended work after the response. For more information, see [Running code after returning a response from an AWS Lambda function](https://aws.amazon.com/blogs/compute/running-code-after-returning-a-response-from-an-aws-lambda-function/).

## Example

Here is a minimal function that waits 10 seconds after returning a response, before the handler returns.

```swift
import AWSLambdaRuntime
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

struct BackgroundProcessingHandler: LambdaWithBackgroundProcessingHandler {
    struct Input: Decodable {
        let message: String
    }

    struct Greeting: Encodable {
        let echoedMessage: String
    }

    typealias Event = Input
    typealias Output = Greeting

    func handle(
        _ event: Event,
        outputWriter: some LambdaResponseWriter<Output>,
        context: LambdaContext
    ) async throws {
        // Return result to the Lambda control plane
        context.logger.debug("BackgroundProcessingHandler - message received")
        try await outputWriter.write(Greeting(echoedMessage: event.message))

        // Perform some background work, e.g:
        context.logger.debug("BackgroundProcessingHandler - response sent. Performing background tasks.")
        try await Task.sleep(for: .seconds(10))

        // Exit the function. All asynchronous work has been executed before exiting the scope of this function.
        // Follows structured concurrency principles.
        context.logger.debug("BackgroundProcessingHandler - Background tasks completed. Returning")
        return
    }
}

let adapter = LambdaCodableAdapter(handler: BackgroundProcessingHandler())
let runtime = LambdaRuntime(handler: adapter)
try await runtime.run()
```

You can learn how to deploy and invoke this function in the [Background tasks example](https://github.com/awslabs/swift-aws-lambda-runtime/tree/main/Examples/BackgroundTasks).

## See also

- <doc:streaming-responses>
- <doc:lambda-handlers>
