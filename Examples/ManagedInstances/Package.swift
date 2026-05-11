// swift-tools-version:6.2

import PackageDescription

let package = Package(
    name: "swift-aws-lambda-runtime-example",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "HelloJSON", targets: ["HelloJSON"]),
        .executable(name: "Streaming", targets: ["Streaming"]),
        .executable(name: "BackgroundTasks", targets: ["BackgroundTasks"]),
    ],
    dependencies: [
        // For local development, uncomment the line below and comment the remote dependency:
        // .package(name: "swift-aws-lambda-runtime", path: "../.."),

        .package(url: "https://github.com/awslabs/swift-aws-lambda-runtime.git", from: "2.9.0"),

        .package(url: "https://github.com/awslabs/swift-aws-lambda-events.git", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "HelloJSON",
            dependencies: [
                .product(name: "AWSLambdaRuntime", package: "swift-aws-lambda-runtime")
            ],
            path: "Sources/HelloJSON"
        ),
        .executableTarget(
            name: "Streaming",
            dependencies: [
                .product(name: "AWSLambdaRuntime", package: "swift-aws-lambda-runtime"),
                .product(name: "AWSLambdaEvents", package: "swift-aws-lambda-events"),
            ],
            path: "Sources/Streaming"
        ),
        .executableTarget(
            name: "BackgroundTasks",
            dependencies: [
                .product(name: "AWSLambdaRuntime", package: "swift-aws-lambda-runtime")
            ],
            path: "Sources/BackgroundTasks"
        ),
    ]
)
