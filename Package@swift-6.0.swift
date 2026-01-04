// swift-tools-version:6.0

import PackageDescription

let defaultSwiftSettings: [SwiftSetting] = [
    .define("FoundationJSONSupport"),
    .define("ServiceLifecycleSupport"),
    .define("LocalServerSupport"),
    .define("ManagedRuntimeSupport"),
    .enableExperimentalFeature(
        "AvailabilityMacro=LambdaSwift 2.0:macOS 15.0"
    ),
]

let package = Package(
    name: "swift-aws-lambda-runtime",
    products: [
        .library(name: "AWSLambdaRuntime", targets: ["AWSLambdaRuntime"]),
        // plugin to package the lambda, creating an archive that can be uploaded to AWS
        // requires Linux or at least macOS v15
        .plugin(name: "AWSLambdaPackager", targets: ["AWSLambdaPackager"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.92.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.8.0"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.3.0"),
        .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", from: "2.9.0"),
    ],
    targets: [
        .target(
            name: "AWSLambdaRuntime",
            dependencies: [
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "DequeModule", package: "swift-collections"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
            ],
            swiftSettings: defaultSwiftSettings
        ),
        .plugin(
            name: "AWSLambdaPackager",
            capability: .command(
                intent: .custom(
                    verb: "archive",
                    description:
                        "Archive the Lambda binary and prepare it for uploading to AWS. Requires docker on macOS or non Amazonlinux 2 distributions."
                ),
                permissions: [
                    .allowNetworkConnections(
                        scope: .docker,
                        reason: "This plugin uses Docker to create the AWS Lambda ZIP package."
                    )
                ]
            )
        ),
        .testTarget(
            name: "AWSLambdaRuntimeTests",
            dependencies: [
                .byName(name: "AWSLambdaRuntime"),
                .product(name: "NIOTestUtils", package: "swift-nio"),
                .product(name: "NIOFoundationCompat", package: "swift-nio"),
            ],
            swiftSettings: defaultSwiftSettings
        ),
        // for perf testing
        .executableTarget(
            name: "MockServer",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
            ],
            swiftSettings: defaultSwiftSettings
        ),
    ]
)
