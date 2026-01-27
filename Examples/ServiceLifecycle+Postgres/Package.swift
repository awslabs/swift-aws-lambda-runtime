// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "LambdaWithServiceLifecycle",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        // For local development (default)
        .package(name: "swift-aws-lambda-runtime", path: "../.."),

        // For standalone usage, comment the line above and uncomment below:
        // .package(url: "https://github.com/awslabs/swift-aws-lambda-runtime.git", from: "2.0.0"),

        .package(url: "https://github.com/awslabs/swift-aws-lambda-events.git", from: "1.4.0"),
        .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.30.0"),
        .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", from: "2.9.1"),
    ],
    targets: [
        .executableTarget(
            name: "LambdaWithServiceLifecycle",
            dependencies: [
                .product(name: "PostgresNIO", package: "postgres-nio"),
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
                .product(name: "AWSLambdaRuntime", package: "swift-aws-lambda-runtime"),
                .product(name: "AWSLambdaEvents", package: "swift-aws-lambda-events"),
            ]
        )
    ]
)
