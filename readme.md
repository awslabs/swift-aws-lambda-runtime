# Swift AWS Lambda Runtime

Develop and deploy AWS Lambda functions written in Swift.

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fawslabs%2Fswift-aws-lambda-runtime%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/awslabs/swift-aws-lambda-runtime)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fawslabs%2Fswift-aws-lambda-runtime%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/awslabs/swift-aws-lambda-runtime)

The Swift AWS Lambda Runtime is an implementation of the [AWS Lambda Runtime API](https://docs.aws.amazon.com/lambda/latest/dg/runtimes-custom.html). It uses an embedded asynchronous HTTP client based on [SwiftNIO](https://github.com/apple/swift-nio) and provides a layered API for building a range of Lambda functions, from simple closures to complex, performance-sensitive event handlers.

## Documentation

**The full documentation lives on the [Swift Package Index](https://swiftpackageindex.com/awslabs/swift-aws-lambda-runtime/documentation/awslambdaruntime).**

New to Swift on Lambda? Start with the [step-by-step tutorial](https://swiftpackageindex.com/awslabs/swift-aws-lambda-runtime/documentation/awslambdaruntime/tutorials/table-of-content). It walks you through writing, building, testing, and deploying your first function.

The documentation also covers:

- [Getting started quickly](https://swiftpackageindex.com/awslabs/swift-aws-lambda-runtime/documentation/awslambdaruntime/quick-setup)
- [Writing your Lambda function](https://swiftpackageindex.com/awslabs/swift-aws-lambda-runtime/documentation/awslambdaruntime/lambda-handlers): JSON and AWS service events
- [Streaming responses](https://swiftpackageindex.com/awslabs/swift-aws-lambda-runtime/documentation/awslambdaruntime/streaming-responses)
- [Background tasks](https://swiftpackageindex.com/awslabs/swift-aws-lambda-runtime/documentation/awslambdaruntime/background-tasks)
- [Swift Service Lifecycle integration](https://swiftpackageindex.com/awslabs/swift-aws-lambda-runtime/documentation/awslambdaruntime/service-lifecycle)
- [Testing your function locally](https://swiftpackageindex.com/awslabs/swift-aws-lambda-runtime/documentation/awslambdaruntime/testing-locally)
- [Using the SwiftPM plugins](https://swiftpackageindex.com/awslabs/swift-aws-lambda-runtime/documentation/awslambdaruntime/using-the-spm-plugins)
- [Deploying your function](https://swiftpackageindex.com/awslabs/swift-aws-lambda-runtime/documentation/awslambdaruntime/deployment): plugin, AWS Console, SAM, and CDK
- [Lambda Managed Instances](https://swiftpackageindex.com/awslabs/swift-aws-lambda-runtime/documentation/awslambdaruntime/managed-instances)

## TL;DR getting started

You need the Swift 6.x toolchain, [Docker](https://docs.docker.com/desktop/install/mac-install/) (or Apple [container](https://github.com/apple/container)) to build for Amazon Linux, and the [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) configured with `aws configure`. On macOS, use macOS 15 (Sequoia) or later.

1. Create an executable project and add the runtime as a dependency.

```bash
mkdir MyLambda && cd MyLambda
swift package init --type executable --name MyLambda
swift package add-dependency https://github.com/awslabs/swift-aws-lambda-runtime.git --from 2.0.0
swift package add-target-dependency AWSLambdaRuntime MyLambda --package swift-aws-lambda-runtime
```

2. Scaffold a minimal function. The runtime ships a plugin that generates a starting point in `Sources/MyLambda/MyLambda.swift`.

```bash
swift package lambda-init --allow-writing-to-package-directory
```

The generated function receives a JSON event and returns a JSON response.

```swift
import AWSLambdaRuntime

struct HelloRequest: Decodable {
    let name: String
    let age: Int
}

struct HelloResponse: Encodable {
    let greetings: String
}

let runtime = LambdaRuntime {
    (event: HelloRequest, context: LambdaContext) in
    HelloResponse(
        greetings: "Hello \(event.name). You look \(event.age > 30 ? "younger" : "older") than your age."
    )
}

try await runtime.run()
```

3. Test it locally. `swift run` starts a local server on port 7000.

```bash
swift run &
curl --header "Content-Type: application/json" \
     --data '{"name":"World","age":30}' \
     http://127.0.0.1:7000/invoke
```

4. Build and package for Amazon Linux, then deploy.

```bash
swift package --allow-network-connections docker lambda-build
swift package --allow-network-connections all:443 lambda-deploy
```

5. Invoke your deployed function.

```bash
aws lambda invoke \
  --function-name MyLambda \
  --payload $(echo '{"name":"World","age":30}' | base64) \
  /dev/stdout
```

For the full walkthrough, see the [getting started guide](https://swiftpackageindex.com/awslabs/swift-aws-lambda-runtime/documentation/awslambdaruntime/quick-setup) and the [tutorial](https://swiftpackageindex.com/awslabs/swift-aws-lambda-runtime/documentation/awslambdaruntime/tutorials/table-of-content).

## Examples

The [Examples](Examples) directory contains complete, runnable functions covering JSON, API Gateway, streaming, background tasks, Service Lifecycle with PostgreSQL, and more.

## Status

The Swift runtime client is [incubating as part of the Swift Server Workgroup incubation process](https://www.swift.org/sswg/incubated-packages.html). It is an experimental package, subject to change, and intended only for evaluation purposes.

Open [issues on GitHub for support requests](https://github.com/awslabs/swift-aws-lambda-runtime/issues).
