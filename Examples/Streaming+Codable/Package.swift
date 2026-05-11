// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "StreamingCodable",
    platforms: [.macOS(.v15)],
    dependencies: [
        // For local development, uncomment the line below and comment the remote dependency:
        // .package(name: "swift-aws-lambda-runtime", path: "../.."),

        .package(url: "https://github.com/awslabs/swift-aws-lambda-runtime.git", from: "2.9.0"),

        .package(url: "https://github.com/awslabs/swift-aws-lambda-events.git", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "StreamingCodable",
            dependencies: [
                .product(name: "AWSLambdaRuntime", package: "swift-aws-lambda-runtime"),
                .product(name: "AWSLambdaEvents", package: "swift-aws-lambda-events"),
            ]
        ),
        .testTarget(
            name: "Streaming+CodableTests",
            dependencies: [
                "StreamingCodable",
                .product(name: "AWSLambdaRuntime", package: "swift-aws-lambda-runtime"),
            ]
        ),
    ]
)
