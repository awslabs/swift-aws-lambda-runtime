# Define Lambda function handlers in Swift

The Lambda function handler is the method in your function code that processes events. When your function is invoked, Lambda runs the handler method. Your function runs until the handler returns a response, exits, or times out.

This page describes how to work with Lambda function handlers in Swift, including project initialization, naming conventions, and best practices. This page also includes an example of a Swift Lambda function that takes in information about an order, produces a text file receipt, and puts this file in an Amazon Simple Storage Service (S3) bucket. For more information about how to deploy your function after writing it, see [Deploy Swift Lambda functions with .zip file archives](swift-package.md).

## Setting up your Swift handler project

When working with Lambda functions in Swift, the process involves writing your code, compiling it, and deploying the compiled artifacts to Lambda. The simplest way to set up a Lambda handler project in Swift is to use the [Swift AWS Lambda Runtime](https://github.com/awslabs/swift-aws-lambda-runtime). Despite its name, the Swift AWS Lambda Runtime is not a managed runtime in the same sense as it is in Lambda for Python, Java, or Node.js. Instead, the Swift AWS Lambda Runtime is a Swift package (`AWSLambdaRuntime`) that supports writing Lambda functions in Swift and interfacing with AWS Lambda's execution environment.

Use the following commands to create a new Swift Lambda function handler project:

```bash
mkdir MyLambda && cd MyLambda
swift package init --type executable --name MyLambda
swift package add-dependency https://github.com/awslabs/swift-aws-lambda-runtime.git --from 3.0.0
swift package add-target-dependency AWSLambdaRuntime MyLambda --package swift-aws-lambda-runtime

```

After the commands run successfully, use the built-in plugin to scaffold a starting point:

```bash
swift package lambda-init --allow-writing-to-package-directory

```

This command generates a `MyLambda.swift` file in the `Sources/MyLambda/` directory. The `Package.swift` file contains metadata about your package and lists its external dependencies.

## Example Swift Lambda function code

The following example Swift Lambda function code takes in information about an order, produces a text file receipt, and puts this file in an Amazon S3 bucket.

**Example — MyLambda.swift Lambda function**

```swift
import AWSLambdaRuntime
import AWSS3
import Foundation

struct Order: Decodable {
    let orderID: String
    let amount: Double
    let item: String
}

struct OrderResponse: Encodable {
    let message: String
}

let runtime = LambdaRuntime {
    (event: Order, context: LambdaContext) in

    let bucketName = Lambda.env("RECEIPT_BUCKET") ?? ""

    let receiptContent = """
    OrderID: \(event.orderID)
    Amount: $\(String(format: "%.2f", event.amount))
    Item: \(event.item)
    """
    let key = "receipts/\(event.orderID).txt"

    let client = try await S3Client()

    let input = PutObjectInput(
        body: .from(data: receiptContent.data(using: .utf8)!),
        bucket: bucketName,
        contentType: "text/plain",
        key: key
    )
    _ = try await client.putObject(input: input)

    return OrderResponse(message: "Success")
}

try await runtime.run()

```

This file contains the following sections of code:

- **import statements**: Use these to import Swift packages and modules that your Lambda function requires.
- **struct Order: Decodable**: Define the shape of the expected input event in this Swift struct. The struct conforms to `Decodable` so the runtime can automatically deserialize the incoming JSON.
- **struct OrderResponse: Encodable**: Define the shape of the response. The struct conforms to `Encodable` so the runtime can automatically serialize the return value to JSON.
- **let runtime = LambdaRuntime { ... }**: This is the main handler closure, which contains your main application logic. The runtime passes an event of the specified input type and a `LambdaContext` object.
- **try await runtime.run()**: This starts the Lambda runtime loop. It receives events from the Lambda service, invokes your handler, and sends back responses.

The following `Package.swift` file accompanies this function:

```swift
// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "MyLambda",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/awslabs/swift-aws-lambda-runtime.git", from: "3.0.0"),
        .package(url: "https://github.com/awslabs/aws-sdk-swift.git", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "MyLambda",
            dependencies: [
                .product(name: "AWSLambdaRuntime", package: "swift-aws-lambda-runtime"),
                .product(name: "AWSS3", package: "aws-sdk-swift"),
            ]
        )
    ]
)

```

For this function to work properly, its execution role must allow the `s3:PutObject` action. Also, ensure that you define the `RECEIPT_BUCKET` environment variable. After a successful invocation, the Amazon S3 bucket should contain a receipt file.

## Valid handler definitions for Swift

Lambda handlers in Swift can be defined using either a closure-based approach or a protocol-based approach.

### Closure-based handler

The most concise way to define a handler uses the `LambdaRuntime` initializer with a closure:

```swift
let runtime = LambdaRuntime {
    (event: Input, context: LambdaContext) in
    // your logic here
    return output
}

try await runtime.run()

```

For this handler:

- `Input` is the deserialized event type. It must conform to `Decodable` so the runtime can convert the incoming JSON to your struct. For example, `Input` can be a custom struct like `Order`, or a predefined event type like `APIGatewayV2Request` from the `AWSLambdaEvents` library.
- `Output` is the serialized return type. It must conform to `Encodable` so the runtime can convert the return value to JSON. For example, `Output` can be a simple type like `String`, or a custom struct as long as it conforms to `Encodable`.
- `context` is of type `LambdaContext`, which provides Lambda-specific metadata such as the request ID of the invocation.
- When your handler throws an error, your function logs the error in Amazon CloudWatch and returns an error response.

### Protocol-based handler

For larger applications, you can define a struct that conforms to the `LambdaHandler` protocol:

```swift
import AWSLambdaRuntime

struct MyHandler: LambdaHandler {
    func handle(
        _ event: Order,
        context: LambdaContext
    ) async throws -> OrderResponse {
        // your logic here
        return OrderResponse(message: "Success")
    }
}

let handler = MyHandler()
let runtime = LambdaRuntime(handler: LambdaCodableAdapter(handler: LambdaHandlerAdapter(handler: handler)))
try await runtime.run()

```

Other valid handler patterns include:

- **Omitting the return type** — If your function doesn't need to return a value (for example, processing SQS messages), you can omit the return statement:```swift let runtime = LambdaRuntime { (event: SQSEvent, context: LambdaContext) in // process event, no return needed }

```

## Handler naming conventions

Lambda handlers in Swift don't have strict naming restrictions. For the closure-based approach, the handler is anonymous. For the protocol-based approach, the `handle` method name is required by the protocol.

For smaller applications, you can use a single `main.swift` file (or a file named after your target) to contain all of your code. For larger projects, you should separate your code into logical modules. For example, you might have the following file structure:

```

/MyLambda ├── Sources/ 
          │ └── MyLambda/ 
          │ ├─── MyLambda.swift # Entry point with handler 
          │ ├─── Services.swift # [Optional] Back-end service calls 
          │ ├─── Models.swift # [Optional] Data models 
          ├── Package.swift

```

## Defining and accessing the input event object

JSON is the most common and standard input format for Lambda functions. In this example, the function expects an input similar to the following:

```json
{
    "orderID": "12345",
    "amount": 199.99,
    "item": "Wireless Headphones"
}

```

In Swift, you define the shape of the expected input event in a struct that conforms to `Decodable`. In this example, we define the following struct to represent an `Order`:

```swift
struct Order: Decodable {
    let orderID: String
    let amount: Double
    let item: String
}

```

This struct matches the expected input shape. The `Decodable` conformance allows the Swift AWS Lambda Runtime to automatically deserialize the incoming JSON into your struct. Within your handler, you can directly access the fields of the event object. For example, `event.orderID` retrieves the value of `orderID` from the original input.

## Pre-defined input event types

There are many pre-defined input event types available in the [Swift AWS Lambda Events](https://github.com/awslabs/swift-aws-lambda-events) package. For example, if you intend to invoke your function with API Gateway, add the following dependency:

```swift
.product(name: "AWSLambdaEvents", package: "swift-aws-lambda-events")

```

Then, use the pre-defined type in your handler:

```swift
import AWSLambdaEvents
import AWSLambdaRuntime

let runtime = LambdaRuntime {
    (event: APIGatewayV2Request, context: LambdaContext) -> APIGatewayV2Response in
    let body = event.body ?? ""
    return APIGatewayV2Response(statusCode: .ok, body: body)
}

try await runtime.run()

```

Refer to the [Swift AWS Lambda Events repository](https://github.com/awslabs/swift-aws-lambda-events) for more information about other pre-defined input event types, including S3, SQS, SNS, CloudWatch, and Cognito events.

## Accessing and using the Lambda context object

The Lambda context object contains information about the invocation, function, and execution environment. The `LambdaContext` is passed directly to your handler. For example, you can use the context object to retrieve the request ID of the current invocation with the following code:

```swift
let runtime = LambdaRuntime {
    (event: Order, context: LambdaContext) in
    let requestID = context.requestID
    // ...
}

```

For more information about the context object, see [Using the Lambda context object to retrieve Swift function information](swift-context.md).

## Using the AWS SDK for Swift in your handler

Often, you'll use Lambda functions to interact with or make updates to other AWS resources. The simplest way to interface with these resources is to use the [AWS SDK for Swift](https://github.com/awslabs/aws-sdk-swift).

To add SDK dependencies to your function, add them in your `Package.swift` file. We recommend only adding the libraries that you need for your function. In the example code earlier, we used the `AWSS3` module. In the `Package.swift` file, you can add this dependency:

```swift
.package(url: "https://github.com/awslabs/aws-sdk-swift.git", from: "1.0.0"),

```

Then add the product to your target:

```swift
.product(name: "AWSS3", package: "aws-sdk-swift"),

```

Import the dependencies directly in your code:

```swift
import AWSS3

```

The example code then initializes an Amazon S3 client as follows:

```swift
let client = try await S3Client()

```

After you initialize your SDK client, you can use it to interact with other AWS services. The example code calls the Amazon S3 `PutObject` API in the handler.

## Accessing environment variables

In your handler code, you can reference any environment variables by using the `Lambda.env()` function or `ProcessInfo`. In this example, we reference the defined `RECEIPT_BUCKET` environment variable using the following line of code:

```swift
let bucketName = Lambda.env("RECEIPT_BUCKET") ?? ""

```

Alternatively, you can use Foundation:

```swift
let bucketName = ProcessInfo.processInfo.environment["RECEIPT_BUCKET"] ?? ""

```

## Using shared state

You can initialize shared resources before creating the `LambdaRuntime`. These resources persist across invocations within the same execution environment. For example, you can initialize an Amazon S3 client outside the handler:

```swift
import AWSLambdaRuntime
import AWSS3

let client = try await S3Client()

let runtime = LambdaRuntime {
    (event: Order, context: LambdaContext) in
    // Use the shared client
    let input = PutObjectInput(
        body: .from(data: "receipt".data(using: .utf8)!),
        bucket: "my-bucket",
        key: "receipts/\(event.orderID).txt"
    )
    _ = try await client.putObject(input: input)
    return OrderResponse(message: "Success")
}

try await runtime.run()

```

For more complex initialization scenarios, use the protocol-based approach with an `init` method:

```swift
struct MyHandler: LambdaHandler {
    let s3Client: S3Client

    init() async throws {
        self.s3Client = try await S3Client()
    }

    func handle(_ event: Order, context: LambdaContext) async throws -> OrderResponse {
        // use self.s3Client
        return OrderResponse(message: "Success")
    }
}

let handler = try await MyHandler()
let runtime = LambdaRuntime(handler: LambdaCodableAdapter(handler: LambdaHandlerAdapter(handler: handler)))
try await runtime.run()

```

## Code best practices for Swift Lambda functions

Adhere to the guidelines in the following list to use best coding practices when building your Lambda functions:

- **Separate the Lambda handler from your core logic.** This allows you to make a more unit-testable function.
- **Minimize the complexity of your dependencies.** Prefer simpler frameworks that load quickly on execution environment startup.
- **Minimize your deployment package size to its runtime necessities.** This will reduce the amount of time that it takes for your deployment package to be downloaded and unpacked ahead of invocation.
- **Take advantage of execution environment reuse to improve the performance of your function.** Initialize SDK clients and database connections outside of the function handler, and cache static assets locally in the `/tmp` directory. Subsequent invocations processed by the same instance of your function can reuse these resources. This saves cost by reducing function run time.
- **To avoid potential data leaks across invocations, don't use the execution environment to store user data, events, or other information with security implications.** If your function relies on a mutable state that can't be stored in memory within the handler, consider creating a separate function or separate versions of a function for each user.
- **Use a keep-alive directive to maintain persistent connections.** Lambda purges idle connections over time. Attempting to reuse an idle connection when invoking a function will result in a connection error. To maintain your persistent connection, use the keep-alive directive associated with your runtime.
- **Use environment variables to pass operational parameters to your function.** For example, if you are writing to an Amazon S3 bucket, instead of hard-coding the bucket name you are writing to, configure the bucket name as an environment variable.
- **Avoid using recursive invocations in your Lambda function**, where the function invokes itself or initiates a process that may invoke the function again. This could lead to unintended volume of function invocations and escalated costs. If you see an unintended volume of invocations, set the function reserved concurrency to `0` immediately to throttle all invocations to the function, while you update the code.
- **Do not use non-documented, non-public APIs in your Lambda function code.** For AWS Lambda managed runtimes, Lambda periodically applies security and functional updates to Lambda's internal APIs. These internal API updates may be backwards-incompatible, leading to unintended consequences such as invocation failures if your function has a dependency on these non-public APIs. See the [API reference](https://docs.aws.amazon.com/lambda/latest/api/welcome.html) for a list of publicly available APIs.
- **Write idempotent code.** Writing idempotent code for your functions ensures that duplicate events are handled the same way. Your code should properly validate events and gracefully handle duplicate events. For more information, see [How do I make my Lambda function idempotent?](https://repost.aws/knowledge-center/lambda-function-idempotent).

