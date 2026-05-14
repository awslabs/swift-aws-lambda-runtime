// swift-tools-version:6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Palindrome",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "PalindromeLambda", targets: ["PalindromeLambda"])
    ],
    dependencies: [
        .package(url: "https://github.com/awslabs/swift-aws-lambda-runtime.git", from: "2.0.0")
    ],
    targets: [
        .executableTarget(
            name: "PalindromeLambda",
            dependencies: [
                .product(name: "AWSLambdaRuntime", package: "swift-aws-lambda-runtime")
            ],
            path: "Sources"
        )
    ]
)
