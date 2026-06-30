// swift-tools-version:6.3

import PackageDescription

let package = Package(
    name: "swift-aws-lambda-runtime-example",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "OCIImage", targets: ["OCIImage"])
    ],
    dependencies: [
        // For local development, uncomment the line below and comment the remote dependency:
        // .package(name: "swift-aws-lambda-runtime", path: "../..")

        .package(url: "https://github.com/awslabs/swift-aws-lambda-runtime.git", from: "2.12.0")
    ],
    targets: [
        .executableTarget(
            name: "OCIImage",
            dependencies: [
                .product(name: "AWSLambdaRuntime", package: "swift-aws-lambda-runtime")
            ],
            path: "Sources"
        )
    ]
)
