// swift-tools-version:6.2

import PackageDescription

let defaultSwiftSettings: [SwiftSetting] =
    [
        .treatAllWarnings(as: .error),
        .enableExperimentalFeature("AvailabilityMacro=LambdaSwift 2.0:macOS 15.0"),

        // https://docs.swift.org/compiler/documentation/diagnostics/nonisolated-nonsending-by-default/
        .enableUpcomingFeature("NonisolatedNonsendingByDefault"),

        // https://github.com/apple/swift-evolution/blob/main/proposals/0335-existential-any.md
        // Require `any` for existential types
        .enableUpcomingFeature("ExistentialAny"),

        // https://github.com/swiftlang/swift-evolution/blob/main/proposals/0444-member-import-visibility.md
        .enableUpcomingFeature("MemberImportVisibility"),

        // https://github.com/swiftlang/swift-evolution/blob/main/proposals/0409-access-level-on-imports.md
        .enableUpcomingFeature("InternalImportsByDefault"),
    ]

let package = Package(
    name: "swift-aws-lambda-runtime",
    // This is a temporary fix to include soto-core dependency for lambda-deploy plugin
    // soto-core has a dependency on swift-crypto that defines
    // a platform requirement on macOS v12.
    // Starting with Swift 6.4, macOS v12 is the default
    // The below line will be removed when we will support 6.4, 6.5, and 6.
    // (end of 2027?)
    platforms: [.macOS(.v12)],
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

        // plugin to package the lambda, creating a binary ZIP or OCI that can be uploaded to AWS
        .plugin(name: "AWSLambdaBuilder", targets: ["AWSLambdaBuilder"]),

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
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.101.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.14.0"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.6.0"),
        .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", from: "2.11.0"),
        .package(url: "https://github.com/soto-project/soto-core.git", from: "7.14.0"),
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
            exclude: ["Docs.docc"],
            swiftSettings: defaultSwiftSettings,
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
        .plugin(
            name: "AWSLambdaBuilder",
            capability: .command(
                intent: .custom(
                    verb: "lambda-build",
                    description:
                        "Compile and archive (zip or oci) the Lambda binary and prepare it for uploading to AWS. Requires docker on macOS or non Amazonlinux 2 distributions."
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
            swiftSettings: defaultSwiftSettings + [
                .treatWarning("ExistentialAny", as: .warning)
            ]
        ),
        .testTarget(
            name: "AWSLambdaRuntimeTests",
            dependencies: [
                .byName(name: "AWSLambdaRuntime"),
                .product(name: "NIOTestUtils", package: "swift-nio"),
                .product(name: "NIOFoundationCompat", package: "swift-nio"),
            ],
            swiftSettings: defaultSwiftSettings,
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
            swiftSettings: defaultSwiftSettings,
        ),
        .testTarget(
            name: "AWSLambdaPluginHelperTests",
            dependencies: [
                .byName(name: "AWSLambdaPluginHelper"),
                .product(name: "Logging", package: "swift-log"),
            ],
            swiftSettings: defaultSwiftSettings,
        ),

    ]
)
