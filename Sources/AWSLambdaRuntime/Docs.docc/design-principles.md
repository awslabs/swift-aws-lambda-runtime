# Design principles

@Metadata {
    @PageKind(article)
    @PageColor(orange)
    @SupportedLanguage(swift)
    @PageImage(source: "lambda.png", alt: "AWS Lambda", purpose: icon)
}

Understand the design goals behind the v2 API of the Swift AWS Lambda Runtime.

## Overview

The [v2 API design document](https://github.com/awslabs/swift-aws-lambda-runtime/blob/main/Sources/AWSLambdaRuntime/Docs.docc/Proposals/0001-v2-api.md) details the v2 API proposal for the swift-aws-lambda-runtime library, which aims to improve the developer experience for building serverless functions in Swift.

The proposal was reviewed and [incorporated feedback from the community](https://forums.swift.org/t/aws-lambda-v2-api-proposal/73819).

## Key design principles

The v2 API prioritizes the following principles:

- **Readability and maintainability**: Extensive use of `async`/`await` improves code clarity and simplifies maintenance.

- **Developer control**: Developers own the `main()` function and can inject dependencies into the `LambdaRuntime`. This lets you manage service lifecycles efficiently using [Swift Service Lifecycle](https://github.com/swift-server/swift-service-lifecycle) for structured concurrency.

- **Simplified Codable support**: The `LambdaCodableAdapter` struct removes the verbose boilerplate previously needed to encode and decode events and responses.

## New capabilities

The v2 API introduces two new features:

- [Response streaming](https://aws.amazon.com/blogs/compute/introducing-aws-lambda-response-streaming/): ideal for handling large responses that need to be sent incrementally.

- [Background work](https://aws.amazon.com/blogs/compute/running-code-after-returning-a-response-from-an-aws-lambda-function/): schedule tasks to run after returning a response to the AWS Lambda control plane.

These capabilities give you greater flexibility and control when building serverless functions in Swift. See <doc:lambda-handlers> for how to use them.
