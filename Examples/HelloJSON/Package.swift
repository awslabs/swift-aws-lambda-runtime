// swift-tools-version:6.1

import PackageDescription

let package = Package(
    name: "swift-aws-lambda-runtime-example",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "HelloJSON", targets: ["HelloJSON"])
    ],
    dependencies: [
        // For local development, uncomment the line below and comment the remote dependency:
        // .package(name: "swift-aws-lambda-runtime", path: "../..")

        .package(url: "https://github.com/awslabs/swift-aws-lambda-runtime.git", from: "2.9.0")
    ],
    targets: [
        .executableTarget(
            name: "HelloJSON",
            dependencies: [
                .product(name: "AWSLambdaRuntime", package: "swift-aws-lambda-runtime")
            ]
        )
    ]
)
