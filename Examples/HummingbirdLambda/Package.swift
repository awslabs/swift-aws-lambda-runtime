// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "HBLambda",
    platforms: [.macOS(.v15)],
    dependencies: [
        // the Swift Lambda Runtime is a dependency of hummingbird-lambda and it exports the runtime
        // no need to import it here

        .package(
            url: "https://github.com/hummingbird-project/hummingbird-lambda.git",
            from: "2.0.1"
        ),
        .package(url: "https://github.com/awslabs/swift-aws-lambda-events.git", from: "1.1.0"),
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
