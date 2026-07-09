// swift-tools-version: 6.3

import PackageDescription

// This example intentionally does NOT enable `NonisolatedNonsendingByDefault` at the
// project level. Instead, it demonstrates the targeted approach: applying
// `nonisolated(nonsending)` directly at the handler and adapter level (see
// `Sources/LambdaStreaming+Codable.swift`) so this module interoperates with the
// swift-aws-lambda-runtime library, which does enable the feature.
//
// To flip the whole project instead, uncomment the line below and remove the explicit
// `nonisolated(nonsending)` annotations from the handler/adapter/closure signatures.
//
let swiftSettings: [SwiftSetting] = [
    // https://docs.swift.org/compiler/documentation/diagnostics/nonisolated-nonsending-by-default/
    // .enableUpcomingFeature("NonisolatedNonsendingByDefault")
]

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
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "Streaming+CodableTests",
            dependencies: [
                "StreamingCodable",
                .product(name: "AWSLambdaRuntime", package: "swift-aws-lambda-runtime"),
            ],
            swiftSettings: swiftSettings
        ),
    ]
)
