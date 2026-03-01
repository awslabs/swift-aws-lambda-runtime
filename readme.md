
This package makes it easy to run AWS Lambda Functions written in Swift.

You can read [the Swift AWS Lambda Runtime documentation](https://swiftpackageindex.com/awslabs/swift-aws-lambda-runtime/2.3.0/documentation/awslambdaruntime) on the Swift Package Index.

This guide contains the following sections:

- [The Swift AWS Lambda Runtime](#the-swift-aws-lambda-runtime)
- [Prerequisites](#prerequisites)
- [Getting started](#getting-started)
- [Developing your Swift Lambda functions](#developing-your-swift-lambda-functions)
- [Testing Locally](#testing-locally)
- [Deploying your Swift Lambda functions](#deploying-your-swift-lambda-functions)
- [Swift AWS Lambda Runtime - Design Principles](#swift-aws-lambda-runtime---design-principles)

The Swift runtime client is [incubating as part of the Swift Server Workgroup incubation process](https://www.swift.org/sswg/incubated-packages.html). It is an experimental package, subject to change, and intended only for evaluation purposes.

Open [issues on GitHub for support requests](https://github.com/awslabs/swift-aws-lambda-runtime/issues).

## The Swift AWS Lambda Runtime

Many modern systems have client components like iOS, macOS or watchOS applications as well as server components that those clients interact with. Serverless functions are often the easiest and most efficient way for client application developers to extend their applications into the cloud.

Serverless functions are increasingly becoming a popular choice for running event-driven or otherwise ad-hoc compute tasks in the cloud. They power mission critical microservices and data intensive workloads. In many cases, serverless functions allow developers to more easily scale and control compute costs given their on-demand nature.

When using serverless functions, attention must be given to resource utilization as it directly impacts the costs of the system. This is where Swift shines! With its low memory footprint, deterministic performance, and quick start time, Swift is a fantastic match for the serverless functions architecture.

Combine this with Swift's developer friendliness, expressiveness, and emphasis on safety, and we have a solution that is great for developers at all skill levels, scalable, and cost effective.

Swift AWS Lambda Runtime was designed to make building Lambda functions in Swift simple and safe. The library is an implementation of the [AWS Lambda Runtime API](https://docs.aws.amazon.com/lambda/latest/dg/runtimes-custom.html) and uses an embedded asynchronous HTTP Client based on [SwiftNIO](http://github.com/apple/swift-nio) that is fine-tuned for performance in the AWS Runtime context. The library provides a multi-tier API that allows building a range of Lambda functions: From quick and simple closures to complex, performance-sensitive event handlers.

## Prerequisites

- Ensure you have the Swift 6.x toolchain installed.  You can [install Swift toolchains](https://www.swift.org/install/macos/) from Swift.org

- When developing on macOS, be sure you use macOS 15 (Sequoia) or a more recent macOS version.

- To build and archive your Lambda function, you need to install [docker](https://docs.docker.com/desktop/install/mac-install/) or Apple [container](https://github.com/apple/container).

- To deploy the Lambda function and invoke it, you must have [an AWS account](https://docs.aws.amazon.com/accounts/latest/reference/manage-acct-creating.html) and [install and configure the `aws` command line](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html).

- Some examples are using [AWS SAM](https://aws.amazon.com/serverless/sam/). Install the [SAM CLI](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html) before deploying these examples.

## Getting started

To get started, read [the Swift AWS Lambda runtime tutorial](https://swiftpackageindex.com/awslabs/swift-aws-lambda-runtime/2.3.0/tutorials/table-of-content). It provides developers with detailed step-by-step instructions to develop, build, and deploy a Lambda function.

We also wrote a comprehensive [deployment guide](https://swiftpackageindex.com/awslabs/swift-aws-lambda-runtime/2.3.0/documentation/awslambdaruntime/deployment).

Or, if you're impatient to start with runtime v2, try these six steps:

The `Examples/_MyFirstFunction` contains a script that goes through the steps described in this section.

If you are really impatient, just type:

```bash
cd Examples/_MyFirstFunction
./create_and_deploy_function.sh
```

Otherwise, continue reading.

1. Create a new Swift executable project

```bash
mkdir MyLambda && cd MyLambda
swift package init --type executable --name MyLambda
```

2. Prepare your `Package.swift` file

    2.1 Add the Swift AWS Lambda Runtime as a dependency

    ```bash
    swift package add-dependency https://github.com/awslabs/swift-aws-lambda-runtime.git --from 2.0.0
    swift package add-target-dependency AWSLambdaRuntime MyLambda --package swift-aws-lambda-runtime
    ```

    2.2 (Optional - only on macOS) Add `platforms` after `name`

    ```
        platforms: [.macOS(.v15)],
    ```

    2.3 Your `Package.swift` file must look like this

    ```swift
    // swift-tools-version: 6.0

    import PackageDescription

    let package = Package(
        name: "MyLambda",
        platforms: [.macOS(.v15)],
        dependencies: [
            .package(url: "https://github.com/awslabs/swift-aws-lambda-runtime.git", from: "2.0.0"),
        ],
        targets: [
            .executableTarget(
                name: "MyLambda",
                dependencies: [
                    .product(name: "AWSLambdaRuntime", package: "swift-aws-lambda-runtime"),
                ]
                ),
        ]
    )
    ```

3. Scaffold a minimal Lambda function

The runtime comes with a plugin to generate the code of a simple AWS Lambda function:

```bash
swift package lambda-init --allow-writing-to-package-directory
```

Your `Sources/main.swift` file must look like this.

```swift
import AWSLambdaRuntime

// in this example we are receiving and responding with strings

let runtime = LambdaRuntime {
    (event: String, context: LambdaContext) in
        return String(event.reversed())
}

try await runtime.run()
```

4. Build & archive the package

The runtime comes with a plugin to compile on Amazon Linux and create a ZIP archive:

```bash
swift package archive --allow-network-connections docker
```

By default, it runs on `docker` but it also allows you to build with [Apple container](https://github.com/apple/container) (it requires disabling the sandbox):

```bash
# Both --disable-sandbox and 
# --allow-network-connections are required 
# until https://github.com/swiftlang/swift-package-manager/issues/9763 is fixed
swift package --disable-sandbox \
              --allow-network-connections docker \
              archive \
              --container-cli container
```

If there is no error, the ZIP archive is ready to deploy.
The ZIP file is located at `.build/plugins/AWSLambdaPackager/outputs/AWSLambdaPackager/MyLambda/MyLambda.zip`

 >[!NOTE]
   > If you encounter Docker credential store errors during the build, remove the `credsStore` entry from your `~/.docker/config.json` file or disable the plugin sandbox with `--disable-sandbox`. See [issue #609](https://github.com/awslabs/swift-aws-lambda-runtime/issues/609) for details.

5. Deploy to AWS

There are multiple ways to deploy to AWS ([SAM](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/what-is-sam.html), [Terraform](https://developer.hashicorp.com/terraform/tutorials/aws-get-started), [AWS Cloud Development Kit (CDK)](https://docs.aws.amazon.com/cdk/v2/guide/getting_started.html), [AWS Console](https://docs.aws.amazon.com/lambda/latest/dg/getting-started.html)) that are covered later in this doc.

Here is how to deploy using the `aws` command line.

```bash
aws lambda create-function \
--function-name MyLambda \
--zip-file fileb://.build/plugins/AWSLambdaPackager/outputs/AWSLambdaPackager/MyLambda/MyLambda.zip \
--runtime provided.al2 \
--handler provided  \
--architectures arm64 \
--role arn:aws:iam::<YOUR_ACCOUNT_ID>:role/lambda_basic_execution
```

The `--architectures` flag is only required when you build the binary on an Apple Silicon machine (Apple M1 or more recent). It defaults to `x64`.

Be sure to replace <YOUR_ACCOUNT_ID> with your actual AWS account ID (for example: 012345678901).

> [!IMPORTANT] 
> Before creating a function, you need to have a `lambda_basic_execution` IAM role in your AWS account.
>
> You can create this role in two ways:
> 1. Using AWS Console
> 2. Running the commands in the `create_lambda_execution_role()` function in [`Examples/_MyFirstFunction/create_iam_role.sh`](https://github.com/awslabs/swift-aws-lambda-runtime/blob/8dff649920ab0c66bb039d15ae48d9d5764db71a/Examples/_MyFirstFunction/create_and_deploy_function.sh#L40C1-L40C31)

6. Invoke your Lambda function

```bash
aws lambda invoke \
--function-name MyLambda \
--payload $(echo \"Hello World\" | base64)  \
out.txt && cat out.txt && rm out.txt
```

This should print

```
{
    "StatusCode": 200,
    "ExecutedVersion": "$LATEST"
}
"dlroW olleH"
```

## Developing your Swift Lambda functions

### Receive and respond with JSON objects

Typically, your Lambda functions will receive an input parameter expressed as JSON and will respond with some other JSON. The Swift AWS Lambda runtime automatically takes care of encoding and decoding JSON objects when your Lambda function handler accepts `Decodable` and returns `Encodable` conforming types.

Here is an example of a minimal function that accepts a JSON object as input and responds with another JSON object.

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

You can learn how to deploy and invoke this function in [the Hello JSON example README file](Examples/HelloJSON/README.md).

### Lambda Streaming Response

You can configure your Lambda function to stream response payloads back to clients. Response streaming can benefit latency sensitive applications by improving time to first byte (TTFB) performance. This is because you can send partial responses back to the client as they become available. Additionally, you can use response streaming to build functions that return larger payloads. Response stream payloads have a soft limit of 200 MB as compared to the 6 MB limit for buffered responses. Streaming a response also means that your function doesn’t need to fit the entire response in memory. For very large responses, this can reduce the amount of memory you need to configure for your function.

Streaming responses incurs a cost. For more information, see [AWS Lambda Pricing](https://aws.amazon.com/lambda/pricing/).

You can stream responses through [Lambda function URLs](https://docs.aws.amazon.com/lambda/latest/dg/urls-configuration.html), the AWS SDK, or using the Lambda [InvokeWithResponseStream](https://docs.aws.amazon.com/lambda/latest/dg/API_InvokeWithResponseStream.html) API. In this example, we create an authenticated Lambda function URL.

#### Simple Streaming Example

Here is an example of a minimal function that streams 10 numbers with an interval of one second for each number.

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

let runtime = LambdaRuntime.init(handler: SendNumbersWithPause())
try await runtime.run()
```

#### Streaming with HTTP Headers and Status Code

When streaming responses, you can also set HTTP status codes and headers before sending the response body. This is particularly useful when your Lambda function is invoked through API Gateway or Lambda function URLs, allowing you to control the HTTP response metadata.

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
                "Cache-Control": "no-cache"
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

let runtime = LambdaRuntime.init(handler: StreamingWithHeaders())
try await runtime.run()
```

The `writeStatusAndHeaders` method allows you to:
- Set HTTP status codes (200, 404, 500, etc.)
- Add custom HTTP headers for content type, caching, CORS, etc.
- Control response metadata before streaming begins
- Maintain compatibility with API Gateway and Lambda function URLs

You can learn how to deploy and invoke this function in [the streaming example README file](Examples/Streaming/README.md).

### Lambda Streaming Response with JSON Input

The Swift AWS Lambda Runtime also provides a convenient interface that combines the benefits of JSON input decoding with response streaming capabilities. This is ideal when you want to receive strongly-typed JSON events while maintaining the ability to stream responses and execute background work.

Here is an example of a function that receives a JSON event and streams multiple responses:

```swift
import AWSLambdaRuntime
import NIOCore

// Define your input event structure
struct StreamingRequest: Decodable {
    let count: Int
    let message: String
    let delayMs: Int?
}

// Use the new streaming handler with JSON decoding
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

This interface provides:
- **Type-safe JSON input**: Automatic decoding of JSON events into Swift structs
- **Streaming responses**: Full control over when and how to stream data back to clients  
- **Background work support**: Ability to execute code after the response stream is finished
- **Familiar API**: Uses the same closure-based pattern as regular Lambda handlers

You can learn how to deploy and invoke this function in [the streaming codable example README file](Examples/StreamingFromEvent/README.md).

### Integration with AWS Services

 Most Lambda functions are triggered by events originating in other AWS services such as `Amazon SNS`, `Amazon SQS` or `AWS APIGateway`.

 The [Swift AWS Lambda Events](http://github.com/awslabs/swift-aws-lambda-events) package includes an `AWSLambdaEvents` module that provides implementations for most common AWS event types further simplifying writing Lambda functions.

> [!IMPORTANT]
> This library has no dependencies on the AWS Lambda Events library. It is safe to use AWS Lambda v1.x with this Lambda Runtime v2.

 Here is an example Lambda function invoked when the AWS APIGateway receives an HTTP request.

 ```swift
import AWSLambdaEvents
import AWSLambdaRuntime

let runtime = LambdaRuntime {
    (event: APIGatewayV2Request, context: LambdaContext) -> APIGatewayV2Response in

    APIGatewayV2Response(statusCode: .ok, body: "Hello World!")
}

try await runtime.run()
```

 You can learn how to deploy and invoke this function in [the API Gateway example README file](Examples/APIGatewayV2/README.md).

### Trace ID Propagation

The runtime automatically propagates the AWS X-Ray trace ID to your handler's async task tree via [ServiceContext](https://github.com/apple/swift-service-context). This is the standard context propagation mechanism in the Swift server ecosystem, allowing any downstream library to access the trace ID without depending on `AWSLambdaRuntime`.

#### Accessing the trace ID from a Lambda handler

```swift
import AWSLambdaRuntime

let runtime = LambdaRuntime {
    (event: String, context: LambdaContext) in

    // from the context instance
    context.logger.info("Trace ID: \(context.traceID)")

    return "OK"
}

try await runtime.run()
```

#### Accessing the trace ID from a downstream library

Libraries that don't depend on `AWSLambdaRuntime` can read the trace ID through `ServiceContext`:

```swift
import ServiceContextModule

func makeHTTPRequest() async throws {
    if let traceID = ServiceContext.current?.traceID {
        // Add X-Amzn-Trace-Id header to outgoing requests
    }
}
```

This enables tracing libraries like [swift-distributed-tracing](https://github.com/apple/swift-distributed-tracing) and OpenTelemetry-Swift to discover the trace ID automatically without coupling to the Lambda runtime.

> [!NOTE]
> In single-concurrency mode, the runtime also sets the `_X_AMZN_TRACE_ID` environment variable for backward compatibility with legacy tooling that reads the trace ID from the process environment. This environment variable is not set in multi-concurrency mode, as environment variables are shared across the process and would be subject to race conditions.

### Integration with Swift Service LifeCycle

The Swift AWS Lambda Runtime provides built-in support for [Swift Service Lifecycle](https://github.com/swift-server/swift-service-lifecycle), allowing you to manage the lifecycle of your Lambda runtime alongside other services like database clients, HTTP clients, or any other resources that need proper initialization and cleanup.

Here's how to integrate your Lambda function with ServiceLifecycle to manage multiple services:

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

You can see a complete working example in the [ServiceLifecycle+Postgres example](Examples/ServiceLifecycle+Postgres/README.md), which demonstrates how to manage a PostgreSQL client alongside the Lambda runtime using ServiceLifecycle.

### Lambda Managed Instances

[Lambda Managed Instances](https://docs.aws.amazon.com/lambda/latest/dg/lambda-managed-instances.html) enables you to run Lambda functions on your current-generation Amazon EC2 instances while maintaining serverless simplicity. This deployment model provides EC2 flexibility and cost optimization by running your functions on customer-owned EC2 instances, while AWS handles all infrastructure management tasks including instance lifecycle, OS and runtime patching, routing, load balancing, and auto-scaling.

To deploy a Swift Lambda function to Lambda Managed Instances, you need to make two key changes to your code:

#### 1. Use `LambdaManagedRuntime` instead of `LambdaRuntime`

Replace your standard `LambdaRuntime` initialization with `LambdaManagedRuntime`:

```swift
import AWSLambdaRuntime

// Standard Lambda function - change this:
// let runtime = LambdaRuntime { ... }

// Lambda Managed Instances - to this:
let runtime = LambdaManagedRuntime {
    (event: HelloRequest, context: LambdaContext) in
    
    HelloResponse(greetings: "Hello \(event.name)!")
}

try await runtime.run()
```

#### 2. Ensure Handler Functions and Structs are `Sendable`

Because Lambda Managed Instances can run functions concurrently on the same EC2 host, your handler functions or the structs containing them must conform to the `Sendable` protocol:

```swift
import AWSLambdaRuntime

// For struct-based handlers, explicitly conform to Sendable
struct MyHandler: LambdaWithBackgroundProcessingHandler, Sendable {
    typealias Event = MyRequest
    typealias Output = MyResponse
    
    func handle(
        _ event: Event,
        outputWriter: some LambdaResponseWriter<Output>,
        context: LambdaContext
    ) async throws {
        // Your handler logic here
        try await outputWriter.write(MyResponse(message: "Processed"))
    }
}

// Just like with LambdaRuntime, use LambdaCodableAdapter to pass it to LambdaManagedruntime
let adapter = LambdaCodableAdapter(handler: MyHandler())
let runtime = LambdaManagedRuntime(handler: adapter)
try await runtime.run()
```

For simple data structures, the Swift compiler automatically infers `Sendable` conformance, but we recommand declaring it explicitly for clarity and safety.

#### Key Benefits

- **EC2 Flexibility**: Run on specialized EC2 instance types including Graviton4 and network-optimized instances
- **Cost Optimization**: Better cost efficiency for sustained workloads
- **Serverless Simplicity**: AWS manages all infrastructure concerns while you focus on code
- **Concurrent Execution**: Functions can run concurrently on the same host for improved throughput

#### Prerequisites

Before deploying to Lambda Managed Instances, you need to:

1. Create a [Lambda Managed Instances capacity provider](https://docs.aws.amazon.com/lambda/latest/dg/lambda-managed-instances-capacity-providers.html)
2. Configure your deployment to reference the capacity provider ARN

You can see complete working examples in the [ManagedInstances example directory](Examples/ManagedInstances/README.md), which demonstrates deploying HelloJSON, Streaming, and BackgroundTasks functions to Lambda Managed Instances using AWS SAM.

For more information, see the [AWS Lambda Managed Instances documentation](https://docs.aws.amazon.com/lambda/latest/dg/lambda-managed-instances.html) and the [execution environment guide](https://docs.aws.amazon.com/lambda/latest/dg/lambda-managed-instances-execution-environment.html).

### Use Lambda Background Tasks

Background tasks allow code to execute asynchronously after the main response has been returned, enabling additional processing without affecting response latency. This approach is ideal for scenarios like logging, data updates, or notifications that can be deferred. The code leverages Lambda's "Response Streaming" feature, which is effective for balancing real-time user responsiveness with the ability to perform extended tasks post-response. For more information about Lambda background tasks, see [this AWS blog post](https://aws.amazon.com/blogs/compute/running-code-after-returning-a-response-from-an-aws-lambda-function/).


Here is an example of a minimal function that waits 10 seconds after it returned a response but before the handler returns.
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
let runtime = LambdaRuntime.init(handler: adapter)
try await runtime.run()
```

You can learn how to deploy and invoke this function in [the background tasks example README file](Examples/BackgroundTasks/README.md).

## Testing Locally

Before deploying your code to AWS Lambda, you can test it locally by running the executable target on your local machine. It will look like this on CLI:

```sh
swift run
```

When not running inside a Lambda execution environment, it starts a local HTTP server listening on port 7000. You can invoke your local Lambda function by sending an HTTP POST request to `http://127.0.0.1:7000/invoke`.

The request must include the JSON payload expected as an `event` by your function. You can create a text file with the JSON payload documented by AWS or captured from a trace.  In this example, we used [the APIGatewayv2 JSON payload from the documentation](https://docs.aws.amazon.com/lambda/latest/dg/services-apigateway.html#apigateway-example-event), saved as `events/create-session.json` text file.

Then we use curl to invoke the local endpoint with the test JSON payload.

```sh
curl -v --header "Content-Type:\ application/json" --data @events/create-session.json http://127.0.0.1:7000/invoke
*   Trying 127.0.0.1:7000...
* Connected to 127.0.0.1 (127.0.0.1) port 7000
> POST /invoke HTTP/1.1
> Host: 127.0.0.1:7000
> User-Agent: curl/8.4.0
> Accept: */*
> Content-Type:\ application/json
> Content-Length: 1160
>
< HTTP/1.1 200 OK
< content-length: 247
<
* Connection #0 to host 127.0.0.1 left intact
{"statusCode":200,"isBase64Encoded":false,"body":"...","headers":{"Access-Control-Allow-Origin":"*","Content-Type":"application\/json; charset=utf-8","Access-Control-Allow-Headers":"*"}}
```
### Modifying the local server URI

By default, when using the local Lambda server during your tests, it listens on `http://127.0.0.1:7000/invoke`.

Some testing tools, such as the [AWS Lambda runtime interface emulator](https://docs.aws.amazon.com/lambda/latest/dg/images-test.html), require a different endpoint, the port might be used, or you may want to bind a specific IP address.

In these cases, you can use three environment variables to control the local server:

- Set `LOCAL_LAMBDA_HOST` to configure the local server to listen on a different TCP address.
- Set `LOCAL_LAMBDA_PORT` to configure the local server to listen on a different TCP port.
- Set `LOCAL_LAMBDA_INVOCATION_ENDPOINT` to force the local server to listen on a different endpoint.

Example:

```sh
LOCAL_LAMBDA_PORT=8080 LOCAL_LAMBDA_INVOCATION_ENDPOINT=/2015-03-31/functions/function/invocations swift run
```

## Deploying your Swift Lambda functions

There is a full deployment guide available in [the documentation](https://swiftpackageindex.com/awslabs/swift-aws-lambda-runtime/2.3.0/documentation/awslambdaruntime/deployment).

There are multiple ways to deploy your Swift code to AWS Lambda. The very first time, you'll probably use the AWS Console to create a new Lambda function and upload your code as a zip file. However, as you iterate on your code, you'll want to automate the deployment process.

To take full advantage of the cloud, we recommend using Infrastructure as Code (IaC) tools like the [AWS Serverless Application Model (SAM)](https://aws.amazon.com/serverless/sam/) or [AWS Cloud Development Kit (CDK)](https://aws.amazon.com/cdk/). These tools allow you to define your infrastructure and deployment process as code, which can be version-controlled and automated.

Alternatively, you might also consider using popular third-party tools like [Serverless Framework](https://www.serverless.com/), [Terraform](https://www.terraform.io/), or [Pulumi](https://www.pulumi.com/) to deploy Lambda functions and create and manage AWS infrastructure.

Here is a short example that shows how to deploy using SAM.

**Prerequisites** : Install the [SAM CLI](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html)

When using SAM, you describe your deployment in a YAML text file.
The [API Gateway example directory](Examples/APIGateway/template.yaml) contains a file named `template.yaml` that you can use as a starting point.

To deploy your Lambda function and create the infrastructure, type the following `sam` command.

```bash
sam deploy \
--resolve-s3 \
--template-file template.yaml \
--stack-name APIGatewayLambda \
--capabilities CAPABILITY_IAM 
```

At the end of the deployment, the script lists the API Gateway endpoint.
The output is similar to this one.

```
-----------------------------------------------------------------------------------------------------------------------------
Outputs                                                                                                                     
-----------------------------------------------------------------------------------------------------------------------------
Key                 APIGatewayEndpoint                                                                                      
Description         API Gateway endpoint URL"                                                                                
Value               https://a5q74es3k2.execute-api.us-east-1.amazonaws.com                                                  
-----------------------------------------------------------------------------------------------------------------------------
```

Please refer to [the full deployment guide available in the documentation](https://swiftpackageindex.com/awslabs/swift-aws-lambda-runtime/2.3.0/documentation/awslambdaruntime/deployment) for more details.

## Swift AWS Lambda Runtime - Design Principles

The [design document](Sources/AWSLambdaRuntime/Docs.docc/Proposals/0001-v2-api.md) details the v2 API proposal for the swift-aws-lambda-runtime library, which aims to enhance the developer experience for building serverless functions in Swift.

The proposal has been reviewed and [incorporated feedback from the community](https://forums.swift.org/t/aws-lambda-v2-api-proposal/73819). The full v2 API design document is available [in this repository](Sources/AWSLambdaRuntime/Docs.docc/Proposals/0001-v2-api.md).

### Key Design Principles

The v2 API prioritizes the following principles:

- Readability and Maintainability: Extensive use of `async`/`await` improves code clarity and simplifies maintenance.

- Developer Control: Developers own the `main()` function and have the flexibility to inject dependencies into the `LambdaRuntime`. This allows you to manage service lifecycles efficiently using [Swift Service Lifecycle](https://github.com/swift-server/swift-service-lifecycle) for structured concurrency.

- Simplified Codable Support: The `LambdaCodableAdapter` struct eliminates the need for verbose boilerplate code when encoding and decoding events and responses.

### New Capabilities

The v2 API introduces two new features:

[Response Streaming](https://aws.amazon.com/blogs/compute/introducing-aws-lambda-response-streaming/): This functionality is ideal for handling large responses that need to be sent incrementally.  

[Background Work](https://aws.amazon.com/blogs/compute/running-code-after-returning-a-response-from-an-aws-lambda-function/): Schedule tasks to run after returning a response to the AWS Lambda control plane.

These new capabilities provide greater flexibility and control when building serverless functions in Swift with the swift-aws-lambda-runtime library.
