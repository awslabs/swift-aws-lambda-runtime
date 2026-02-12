# Getting Started Quickly

@Metadata {
    @PageKind(article)
    @PageColor(orange)
    @SupportedLanguage(swift)
    @PageImage(source: "lambda.png", alt: "AWS Lambda", purpose: icon)
}

Learn how to create your first project in 3 minutes.

Follow these instructions to get a high-level overview of the steps to write, test, and deploy your first Lambda function written in Swift.

For a detailed step-by-step instruction, follow the tutorial instead.

<doc:/tutorials/table-of-content>

For the impatient, keep reading.

### High-level instructions

Follow these 6 steps to write, test, and deploy a Lambda function in Swift.

1. Create a Swift project for an executable target 

```sh
swift package init --type executable 
```

2. Add dependencies on `AWSLambdaRuntime` library 

```swift
// swift-tools-version:6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "YourProjetName",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .executable(name: "MyFirstLambdaFunction", targets: ["MyFirstLambdaFunction"]),
    ],
    dependencies: [
        .package(url: "https://github.com/awslabs/swift-aws-lambda-runtime.git", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "MyFirstLambdaFunction",
            dependencies: [
                .product(name: "AWSLambdaRuntime", package: "swift-aws-lambda-runtime"),
            ],
            path: "Sources"
        ),
    ]
)
```

3. Write your function code.

Create an instance of `LambdaRuntime` and pass a function as a closure. The function has this signature: `(_: Event, context: LambdaContext) async throws -> Output` (as defined in the `LambdaHandler` protocol). `Event` must be `Decodable`. `Output` must be `Encodable`.

If your Lambda function is invoked by another AWS service, use the `AWSLambdaEvent` library at [https://github.com/awslabs/swift-aws-lambda-events](https://github.com/awslabs/swift-aws-lambda-events) to represent the input event.

Finally, call `runtime.run()` to start the event loop.

```swift
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

4. Test your code locally 

```sh
swift run  # this starts a local server on port 7000

# Switch to another Terminal tab

curl --header "Content-Type: application/json" \
     --request POST                            \
     --data '{"name": "Seb", "age": 50}'       \
     http://localhost:7000/invoke

{"greetings":"Hello Seb. You look younger than your age."}
```

5. Build and package your code for AWS Lambda 

AWS Lambda runtime runs on Amazon Linux. You must compile your code for Amazon Linux.

> Be sure to have [Docker](https://docs.docker.com/desktop/install/mac-install/) installed for this step.

```sh
swift package --allow-network-connections docker archive

-------------------------------------------------------------------------
building "MyFirstLambdaFunction" in docker
-------------------------------------------------------------------------
updating "swift:amazonlinux2" docker image
  amazonlinux2: Pulling from library/swift
  Digest: sha256:5b0cbe56e35210fa90365ba3a4db9cd2b284a5b74d959fc1ee56a13e9c35b378
  Status: Image is up to date for swift:amazonlinux2
  docker.io/library/swift:amazonlinux2
building "MyFirstLambdaFunction"
  Building for production...
...
-------------------------------------------------------------------------
archiving "MyFirstLambdaFunction"
-------------------------------------------------------------------------
1 archive created
  * MyFirstLambdaFunction at /Users/YourUserName/MyFirstLambdaFunction/.build/plugins/AWSLambdaPackager/outputs/AWSLambdaPackager/MyFirstLambdaFunction/MyFirstLambdaFunction.zip


cp .build/plugins/AWSLambdaPackager/outputs/AWSLambdaPackager/MyFirstLambdaFunction/MyFirstLambdaFunction.zip ~/Desktop
```

6. Deploy on AWS Lambda

> Be sure [to have an AWS Account](https://docs.aws.amazon.com/accounts/latest/reference/manage-acct-creating.html) to follow these steps.

- Connect to the [AWS Console](https://console.aws.amazon.com)
- Navigate to Lambda 
- Create a function
- Select **Provide your own bootstrap on Amazon Linux 2** as **Runtime**
- Select an **Architecture** that matches the one of the machine where you build the code. Select **x86_64** when you build on Intel-based Macs or **arm64** for Apple Silicon-based Macs.
- Upload the ZIP create during step 5
- Select the **Test** tab, enter a test event such as `{"name": "Seb", "age": 50}` and select **Test**

If the test succeeds, you will see the result: `{"greetings":"Hello Seb. You look younger than your age."}`.


Congratulations 🎉! You just wrote, test, build, and deployed a Lambda function written in Swift.
