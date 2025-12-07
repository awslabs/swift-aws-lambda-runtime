// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "HBLambda",
    platforms: [.macOS(.v15)],
    dependencies: [
        // For local development (default)
        // .package(name: "swift-aws-lambda-runtime", path: "../.."),

        // For standalone usage, comment the line above and uncomment below:
        // .package(url: "https://github.com/awslabs/swift-aws-lambda-runtime.git", from: "2.0.0"),

        .package(
            url: "https://github.com/hummingbird-project/hummingbird-lambda.git",
            branch: "main"
        ),
        .package(url: "https://github.com/awslabs/swift-aws-lambda-events.git", from: "1.4.0"),
    ],
    targets: [
        .executableTarget(
            name: "HBLambda",
            dependencies: [
                .product(name: "HummingbirdLambda", package: "hummingbird-lambda"),
                .product(name: "AWSLambdaEvents", package: "swift-aws-lambda-events"),
            ]
        )
    ]
)
