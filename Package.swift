// swift-tools-version:6.1

import PackageDescription

let defaultSwiftSettings: [SwiftSetting] =
    [
        .enableExperimentalFeature(
            "AvailabilityMacro=LambdaSwift 2.0:macOS 15.0"
        )
    ]

let package = Package(
    name: "swift-aws-lambda-runtime",
    // Required because soto-core declares platforms: [.macOS(.v10_15)] in its Package.swift.
    // SwiftPM rejects executable targets whose platform minimum is below their dependencies'.
    // Without this declaration the package defaults to macOS 10.13, causing a planning error.
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "AWSLambdaRuntime", targets: ["AWSLambdaRuntime"]),

        //
        // The plugins
        // 'lambda-init' creates a new Lambda function
        // 'lambda-build' packages the Lambda function
        // 'lambda-deploy' deploys the Lambda function
        //
        //  Plugins requires Linux or at least macOS v15
        //

        // plugin to create a new Lambda function, based on a template
        .plugin(name: "AWSLambdaInitializer", targets: ["AWSLambdaInitializer"]),

        // plugin to package the lambda, creating an archive that can be uploaded to AWS
        .plugin(name: "AWSLambdaBuilder", targets: ["AWSLambdaBuilder"]),

        // legacy 'archive' command — deprecated passthrough to lambda-build
        .plugin(name: "AWSLambdaPackager", targets: ["AWSLambdaPackager"]),

        // plugin to deploy a Lambda function
        .plugin(name: "AWSLambdaDeployer", targets: ["AWSLambdaDeployer"]),
    ],
    traits: [
        "ManagedRuntimeSupport",
        "FoundationJSONSupport",
        "ServiceLifecycleSupport",
        "LocalServerSupport",
        .default(
            enabledTraits: [
                "ManagedRuntimeSupport",
                "FoundationJSONSupport",
                "ServiceLifecycleSupport",
                "LocalServerSupport",
            ]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.99.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.12.0"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.5.0"),
        .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", from: "2.11.0"),
        .package(url: "https://github.com/soto-project/soto-core.git", from: "7.13.0"),
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
                .product(
                    name: "ServiceLifecycle",
                    package: "swift-service-lifecycle",
                    condition: .when(traits: ["ServiceLifecycleSupport"])
                ),
            ],
            swiftSettings: defaultSwiftSettings
        ),
        .plugin(
            name: "AWSLambdaInitializer",
            capability: .command(
                intent: .custom(
                    verb: "lambda-init",
                    description:
                        "Create a new Lambda function in the current project directory."
                ),
                permissions: [
                    .writeToPackageDirectory(reason: "Create a file with an HelloWorld Lambda function.")
                ]
            ),
            dependencies: [
                .target(name: "AWSLambdaPluginHelper")
            ]
        ),
        // keep this one (with "archive") to not break workflows
        // Uses its own Plugin.swift that emits a deprecation warning then delegates to the helper
        .plugin(
            name: "AWSLambdaPackager",
            capability: .command(
                intent: .custom(
                    verb: "archive",
                    description:
                        "Archive the Lambda binary and prepare it for uploading to AWS. (Deprecated: use lambda-build instead)"
                ),
                permissions: [
                    .allowNetworkConnections(
                        scope: .docker,
                        reason: "This plugin uses Docker to create the AWS Lambda ZIP package."
                    )
                ]
            ),
            dependencies: [
                .target(name: "AWSLambdaPluginHelper")
            ]
        ),
        .plugin(
            name: "AWSLambdaBuilder",
            capability: .command(
                intent: .custom(
                    verb: "lambda-build",
                    description:
                        "Compile and archive (zip) the Lambda binary and prepare it for uploading to AWS. Requires docker on macOS or non Amazonlinux 2 distributions."
                ),
                permissions: [
                    .allowNetworkConnections(
                        scope: .docker,
                        reason: "This plugin uses Docker to compile code for Amazon Linux."
                    )
                ]
            ),
            dependencies: [
                .target(name: "AWSLambdaPluginHelper")
            ]
        ),
        .plugin(
            name: "AWSLambdaDeployer",
            capability: .command(
                intent: .custom(
                    verb: "lambda-deploy",
                    description:
                        "Deploy the Lambda function. You must have an AWS account and an access key and secret access key."
                ),
                permissions: [
                    .allowNetworkConnections(
                        scope: .all(ports: [443]),
                        reason: "This plugin uses the AWS Lambda API to deploy the function."
                    )
                ]
            ),
            dependencies: [
                .target(name: "AWSLambdaPluginHelper")
            ]
        ),
        .executableTarget(
            name: "AWSLambdaPluginHelper",
            dependencies: [
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "SotoCore", package: "soto-core"),
            ],
            swiftSettings: defaultSwiftSettings
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
        .testTarget(
            name: "AWSLambdaPluginHelperTests",
            dependencies: [
                .byName(name: "AWSLambdaPluginHelper"),
                .product(name: "Logging", package: "swift-log"),
            ],
            swiftSettings: defaultSwiftSettings
        ),

    ]
)
