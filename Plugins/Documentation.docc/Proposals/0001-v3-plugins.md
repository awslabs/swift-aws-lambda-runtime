# v2 Plugin Proposal for swift-aws-lambda-runtime

`swift-aws-lambda-runtime` is a library for the Swift on Server ecosystem. The initial version of the library focused on the API, enabling developers to write Lambda functions in the Swift programming language. The library provided developers with basic support for building and packaging their functions.

We believe it is time to consider the end-to-end developer experience, from project scaffolding to deployment, taking into account the needs of Swift developers that are new to AWS and Lambda.

This document describes a proposal for the v2 plugins for `swift-aws-lambda-runtime`. The plugins will focus on project scaffolding, building, archiving, and deployment of Lambda functions.

## Overview

Versions:

* v1 (2024-12-25): Initial version
* v2 (2025-03-13):
- Include [comments from the community](https://forums.swift.org/t/lambda-plugins-for-v2/76859).
- [init] Add the templates for `main.swift`
- [build] Add the section **Cross-compiling options**
- [deploy] Add details about locating AWS Credentials.
- [deploy] Add `--input-path` parameter.
- [deploy] Add details how the function name is computed.
- [deploy] Add `--architecture` option and details how the default is computed.
* v3 (2026-02-17):
- [build] Add `--container-cli` option to support Apple's `container` CLI as an alternative to Docker (addresses [#644](https://github.com/awslabs/swift-aws-lambda-runtime/issues/644)).
- [build] Add the section **Container CLI options**

## Motivation

The current version of `swift-aws-lambda-runtime` provides a solid foundation for Swift developers to write Lambda functions. However, the developer experience can be improved. For example, the current version does not provide any support for project scaffolding or deployment of Lambda functions.

This creates a high barrier to entry for Swift developers new to AWS and Lambda, as well as for AWS professionals learning Swift. We propose to lower this barrier by providing a set of plugins that will assist developers in creating, building, packaging, and deploying Lambda functions.

As a source of inspiration, we looked at the Rust community, which created Cargo-Lambda ([https://www.cargo-lambda.info/guide/what-is-cargo-lambda.html](https://www.cargo-lambda.info/guide/what-is-cargo-lambda.html)). Cargo-Lambda helps developers deploy Rust Lambda functions. We aim to provide a similar experience for Swift developers.

### Current Limitations

The current version of the `archive` plugin support the following tasks:

* The cross-compilation using Docker.
* The archiving of the Lambda function and it's resources as a ZIP file.

The current version of `swift-aws-lambda-runtime` does not provide support for project **scaffolding** or **deployment** of Lambda functions. This makes it difficult for Swift developers new to AWS and Lambda, or AWS Professionals new to Swift, to get started.

### New Plugins

To address the limitations of the `archive` plugin, we propose creating three new plugins:

* `lambda-init`: This plugin will assist developers in creating a new Lambda project from scratch by scaffolding the project structure and its dependencies.

* `lambda-build`: This plugin will help developers build and package their Lambda function (similar to the current `archive` plugin). This plugin will allow for multiple cross-compilation options. We will retain the current Docker-based cross-compilation but will also provide a way to cross-compile without Docker, such as using the [Swift Static Linux SDK](https://www.swift.org/documentation/articles/static-linux-getting-started.html) (with musl) or a (non-existent at the time of this writing) custom Swift SDK for Amazon Linux (built with the [Custom SDK Generator](https://github.com/swiftlang/swift-sdk-generator)). The plugin will also provide an option to package the binary as a ZIP file or as a Docker image.

* `lambda-deploy`: This plugin will assist developers in deploying their Lambda function to AWS. This plugin will handle the deployment of the Lambda function, including the creation of the IAM role, the creation of the Lambda function, and the optional configuration of a Lambda function URL.

We may consider additional plugins in a future release. For example, we could consider a plugin to help developers invoke their Lambda function (`lambda-invoke`) or to monitor CloudWatch logs (`lambda-logs`).

## Detailed Solution

The proposed solution consists of three new plugins: `lambda-init`, `lambda-build`, and `lambda-deploy`. These plugins will assist developers in creating, building, packaging, and deploying Lambda functions.

### Create a New Project (lambda-init)

The `lambda-init` plugin will assist developers in creating a new Lambda project from scratch. The plugin will scaffold the project code. It will create a ready-to-build `main.swift` file containing a simple Lambda function. The plugin will allow users to choose from a selection of basic templates, such as a simple "Hello World" Lambda function or a function invoked by a URL.

The plugin cannot be invoked without the required dependency on `swift-aws-lambda-runtime` project being configured in `Package.swift`. The process of creating a new project will consist of three steps and four commands, all executable from the command line:

```bash
# Step 1: Create a new Swift executable package
swift package init --type executable --name MyLambda

# Step 2: Add the Swift AWS Lambda Runtime dependency
swift package add-dependency https://github.com/awslabs/swift-aws-lambda-runtime.git --branch main
swift package add-target-dependency AWSLambdaRuntime MyLambda --package swift-aws-lambda-runtime

# Step 3: Call the lambda-init plugin
swift package lambda-init
```

The plugin will offer the following options:

```text
OVERVIEW: A SwiftPM plugin to scaffold a Hello World Lambda function.

   By default, it creates a Lambda function that receives a JSON document and responds with another JSON document.

USAGE: swift package lambda-init
                    [--help] [--verbose]
                    [--with-url]
                    [--allow-writing-to-package-directory]

OPTIONS:
--with-url                            Create a Lambda function exposed by a URL
--allow-writing-to-package-directory  Don't ask for permission to write files.
--verbose                             Produce verbose output for debugging.
--help                                Show help information.
```

The initial implementation will use hardcoded templates. In a future release, we might consider fetching the templates from a GitHub repository and allowing developers to create custom templates.

The default templates are currently implemented in the [sebsto/new-plugins branch of this repo](https://github.com/sebsto/swift-aws-lambda-runtime/blob/sebsto/new-plugins/Sources/AWSLambdaPluginHelper/lambda-init/Template.swift).

### Default template 

```swift
import AWSLambdaRuntime

// the data structure to represent the input parameter
struct HelloRequest: Decodable {
    let name: String
    let age: Int
}

// the data structure to represent the output response
struct HelloResponse: Encodable {
    let greetings: String
}

// in this example we receive a HelloRequest JSON and we return a HelloResponse JSON    

// the Lambda runtime
let runtime = LambdaRuntime {
    (event: HelloRequest, context: LambdaContext) in

    HelloResponse(
        greetings: "Hello \(event.name). You look \(event.age > 30 ? "younger" : "older") than your age."
    )
}

// start the loop
try await runtime.run() 
```

### URL Template 

```swift
import AWSLambdaRuntime
import AWSLambdaEvents

// in this example we receive a FunctionURLRequest and we return a FunctionURLResponse
// https://docs.aws.amazon.com/lambda/latest/dg/urls-invocation.html#urls-payloads

let runtime = LambdaRuntime {
        (event: FunctionURLRequest, context: LambdaContext) -> FunctionURLResponse in
        
        guard let name = event.queryStringParameters?["name"] else {
            return FunctionURLResponse(statusCode: .badRequest)
        }

        return FunctionURLResponse(statusCode: .ok, body: #"{ "message" : "Hello \#\#(name)" } "#)
}

try await runtime.run()
```

### Build and Package (lambda-build)

The `lambda-build` plugin will assist developers in building and packaging their Lambda function. It will allow for multiple cross-compilation options. We will retain the current Docker-based cross-compilation but also provide a way to cross-compile without Docker, such as using the Swift Static Linux SDK (with musl) or a custom Swift SDK for Amazon Linux.

We also propose to automatically strip the binary of debug symbols (`-Xlinker -s`) to reduce the size of the ZIP file. Our tests showed that this can reduce the size by up to 50%. An option to disable stripping will be provided.

The `lambda-build` plugin is similar to the existing `archive` plugin. We propose to keep the same interface to facilitate migration of existing projects and CI chains. If technically feasible, we will also consider keeping the `archive` plugin as an alias to the `lambda-build` plugin.

The plugin interface is based on the existing `archive` plugin, with the addition of the `--no-strip` and `--cross-compile` options:

```text
OVERVIEW: A SwiftPM plugin to build and package your Lambda function.

REQUIREMENTS: To use this plugin, Docker or Apple container must be installed and running
              (when using docker or container cross-compilation methods).

USAGE: swift package archive
            [--help] [--verbose]
            [--output-directory <path>]
            [--products <list of products>]
            [--configuration debug | release]
            [--swift-version <version>]
            [--base-docker-image <docker_image_name>]
            [--disable-docker-image-update]
            [--no-strip]
            [--cross-compile <value>]
            [--container-cli <value>]
            [--allow-network-connections docker]

OPTIONS:
--output-directory <path>     The path of the binary package.
                                (default: .build/plugins/AWSLambdaPackager/outputs/...)
--products <list>             The list of executable targets to build.
                                (default: taken from Package.swift)
--configuration <name>        The build configuration (debug or release)
                                (default: release)
--swift-version <version>       The Swift version to use for building.
                                (default: latest)
                                This parameter cannot be used with --base-docker-image.
--base-docker-image <name>    The name of the base Docker image to use for the build.
                                (default: swift-<version>:amazonlinux2)
                                This parameter cannot be used with --swift-version.
                                This parameter cannot be used with a value other than Docker provided to --cross-compile.
--disable-docker-image-update Do not update the Docker image before building.
--no-strip                    Do not strip the binary of debug symbols.
--cross-compile <value>       Cross-compile the binary using the specified method.
                                (default: docker) Accepted values are: docker, swift-static-sdk, custom-sdk
--container-cli <value>       Specify the container CLI to use for Docker-based builds.
                                (default: docker) Accepted values are: docker, container
                                This parameter is only used when --cross-compile is set to docker.
```

#### Cross compiling options

We propose to release an initial version based on the current `archive` plugin implementation, which uses docker.  But for the future, we would like to explore the possibility to cross compile with a custom Swift SDK for Amazon Linux. Our [initial tests](https://github.com/swiftlang/swift-sdk-generator/issues/138#issuecomment-2719540021) demonstrated it is possible to build such an SDK using the Swift SDK Generator project.

For an ideal developer experience, we would imagine the following sequence:

- developer runs `swift package build --cross-compile custom-sdk`
- the plugin checks if the custom sdk is installed on the machine (`swift sdk list`) [questions : is it possible to call `swift` from a package ? Should we check the file systems instead ? Should this work on multiple OSes, such as macOS and Linux? ]
- if not installed or outdated, the plugin downloads a custom SDK from a safe source and installs it [questions : who should maintain such SDK binaries? Where to host them? We must have a kind of signature to ensure the SDK has not been modified. How to manage Swift version and align with the local toolchain?]
- the plugin build the archive using the custom sdk

#### Container CLI options

The plugin supports using different container CLIs to build Lambda packages. By default, it uses Docker, but it can also use Apple's `container` CLI on macOS, which provides native support for OCI (Open Container Initiative) images.

**Supported Container CLIs:**

- **Docker** (default): Uses the standard Docker CLI
  - Pull images: `docker pull <image>`
  - Run containers: `docker run --rm -v <volume> -w <workdir> <image> bash -cl "<cmd>"`

- **Apple container**: Uses Apple's native container CLI (available on macOS)
  - Pull images: `container image pull <image>`
  - Run containers: `container run --rm -v <volume> -w <workdir> <image> bash -cl "<cmd>"`

**Configuration:**

The container CLI can be specified via the command-line flag: `--container-cli docker` or `--container-cli container`. If not specified, the plugin defaults to `docker`.

**Example usage:**

```bash
# Use Docker (default)
swift package lambda-build

# Use Apple container
swift package lambda-build --container-cli container
```

**Requirements:**

- When using `docker`, Docker Desktop or Docker Engine must be installed and running
- When using `container`, Apple's container CLI must be installed and running
- The `--container-cli` option is only applicable when using Docker-based cross-compilation (`--cross-compile docker`)

### Deploy (lambda-deploy)

The `lambda-deploy` plugin will assist developers in deploying their Lambda function to AWS. It will handle the deployment process, including creating the IAM role, the Lambda function itself, and optionally configuring a Lambda function URL.

The plugin will not depends on nay third-party library. It will interact directly with the AWS REST API, without using the AWS SDK fro Swift or Soto.

Users will need to provide AWS access key and secret access key credentials. The plugin will attempt to locate these credentials in standard locations. It will first check for the `~/.aws/credentials` file, then the environment variables `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and (optional) `AWS_SESSION_TOKEN`. Finally, it will check the [meta data service v2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/configuring-instance-metadata-service.html) in case the plugin runs from a virtual machine (Amazon EC2) or a container (Amazon ECS or AMazon EKS).

The plugin supports deployment through either the REST and Base64 payload or by uploading the code to a temporary S3 bucket. Refer to [the `Function Code` section](https://docs.aws.amazon.com/lambda/latest/api/API_FunctionCode.html) of the [CreateFunction](https://docs.aws.amazon.com/lambda/latest/dg/API_CreateFunction.html) API for more details.

The plugin will use teh function name as defined in the `executableTarget` in `Package.swift`. This approach is similar to how the `archive` plugin works today.

The plugin can deploy to multiple regions. Users can specify the desired region as a command-line argument.

In addition to deploying the Lambda function, the plugin can also create an IAM role for it. Users can specify the IAM role name as a command-line argument. If no role name is provided, the plugin will create a new IAM role with the necessary permissions for the Lambda function.

The plugin allows developers to update the code for an existing Lambda function. The update command remains the same as for initial deployment. The plugin will detect whether the function already exists and update the code accordingly.

Finally, the plugin can help developers delete a Lambda function and its associated IAM role.

An initial version of this plugin might look like this:

```text
"""
OVERVIEW: A SwiftPM plugin to deploy a Lambda function.

USAGE: swift package lambda-deploy
                        [--with-url]
                        [--region <value>]
                        [--iam-role <value>]
                        [--delete]
                        [--help] [--verbose]

OPTIONS:
--region                   The AWS region to deploy the Lambda function to.
                              (default is us-east-1)
--iam-role                 The name of the IAM role to use for the Lambda function.
                           when none is provided, a new role will be created.
--input-directory  <path>  The path of the binary package (zip file) to deploy
                              (default: .build/plugins/AWSLambdaPackager/outputs/...)
--architecture x64 | arm64 The target architecture of the Lambda function
                              (default: the architecture of the machine where the plugin runs)                              
--with-url                 Add an URL to access the Lambda function
--delete                   Delete the Lambda function and its associated IAM role
--verbose                  Produce verbose output for debugging.
--help                     Show help information.
"""
```

In a future version, we might consider adding an `--export` option that would easily migrate the current deployment to an infrastructure as code (IaC) tool, such as AWS SAM, AWS CDK, or Swift Cloud.

### Dependencies

One of the design objective of the Swift AWS Lambda Runtime is to minimize its dependencies on other libraries.

Therefore, minimizing dependencies is a key priority for the new plugins. We aim to avoid including unnecessary dependencies, such as the AWS SDK for Swift or Soto, for the `lambda-deploy` plugin.

Four essential dependencies have been identified to implement the plugins:

* an command line argument parser
* an HTTP client
* a library to sign AWS requests
* a library to calculate HMAC-SHA256 (used in the AWS signing process)

These functionalities can be incorporated by vending source code from other projects. We will consider the following options:

**Argument Parser:**

* We propose to leverage the `ArgumentExtractor` from the `swift-package-manager` project ([https://github.com/swiftlang/swift-package-manager/blob/main/Sources/PackagePlugin/ArgumentExtractor.swift](https://github.com/swiftlang/swift-package-manager/blob/main/Sources/PackagePlugin/ArgumentExtractor.swift)). This is a simple argument parser used by the Swift Package Manager. The relevant files will be copied into the plugin.

**HTTP Client:**

* We will utilize the `URLSession` provided by `FoundationNetworking`. No additional dependencies will be introduced for the HTTP client.

**AWS Request Signing:**

* To interact with the AWS REST API, requests must be signed. We will include the `AWSRequestSigner` from [the `aws-signer-v4` project](https://github.com/adam-fowler/aws-signer-v4). This is a simple library that signs requests using AWS Signature Version 4. The relevant files will be copied into the plugin.

**HMAC-SHA256 Implementation:**

* The `AWSRequestSigner` has a dependency on the `swift-crypto` library. We will consider two options:
    * Include the HMAC-SHA256 implementation from the popular `CryptoSwift` library ([https://github.com/krzyzanowskim/CryptoSwift](https://github.com/krzyzanowskim/CryptoSwift)), which provides a wide range of cryptographic functions. The relevant files will be copied into the plugin.
    * Develop a clean implementation of the HMAC-SHA256 algorithm. This is a relatively simple algorithm used for request signing.

The dependencies will be vendored within the plugin and will not be listed as dependencies in the `Package.swift` file.

If we follow that plan, the following files will be copied into the plugin, without modifications from their original projects:

```text
Sources/AWSLambdaPluginHelper/Vendored
├── crypto
│   ├── Array+Extensions.swift
│   ├── Authenticator.swift
│   ├── BatchedCollections.swift
│   ├── Bit.swift
│   ├── Collections+Extensions.swift
│   ├── Digest.swift
│   ├── DigestType.swift
│   ├── Generics.swift
│   ├── HMAC.swift
│   ├── Int+Extension.swift
│   ├── NoPadding.swift
│   ├── Padding.swift
│   ├── SHA1.swift
│   ├── SHA2.swift
│   ├── SHA3.swift
│   ├── UInt16+Extension.swift
│   ├── UInt32+Extension.swift
│   ├── UInt64+Extension.swift
│   ├── UInt8+Extension.swift
│   ├── Updatable.swift
│   ├── Utils.swift
│   └── ZeroPadding.swift
├── signer
│   ├── AWSCredentials.swift
│   └── AWSSigner.swift
└── spm
    └── ArgumentExtractor.swift
```

### Implementation

SwiftPM plugins from a same project can not share code in between sources files or using a shared Library target. The recommended way to share code between plugins is to create an executable target to implement the plugin functionalities and to implement the plugin as a thin wrapper that invokes the executable target.

We propose to add an executable target and three plugins to the `Package.swift` file of the `swift-aws-lambda-runtime` package.

```swift
let package = Package(
    name: "swift-aws-lambda-runtime",
    platforms: [.macOS(.v15)],
    products: [

        //
        // The runtime library targets
        //

        // ... unchanged ...

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

        // plugin to deploy a Lambda function
        .plugin(name: "AWSLambdaDeployer", targets: ["AWSLambdaDeployer"]),

        //
        // Testing targets
        //
        // ... unchanged ...
    ],
    dependencies: [ // unchanged
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.76.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.4"),
    ],
    targets: [

        // library target, unchanged 
        // ....

        //
        // The plugins targets
        //
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
        // This will be deprecated at some point in the future
        //        .plugin(
        //            name: "AWSLambdaPackager",
        //            capability: .command(
        //                intent: .custom(
        //                    verb: "archive",
        //                    description:
        //                        "Archive the Lambda binary and prepare it for uploading to AWS. Requires docker on macOS or non Amazonlinux 2 distributions."
        //                ),
        //                permissions: [
        //                    .allowNetworkConnections(
        //                        scope: .docker,
        //                        reason: "This plugin uses Docker to create the AWS Lambda ZIP package."
        //                    )
        //                ]
        //            ),
        //            path: "Plugins/AWSLambdaBuilder" // same sources as the new "lambda-build" plugin
        //        ),
        .plugin(
            name: "AWSLambdaBuilder",
            capability: .command(
                intent: .custom(
                    verb: "lambda-build",
                    description:
                        "Archive the Lambda binary and prepare it for uploading to AWS. Requires docker on macOS or non Amazonlinux 2 distributions."
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
            name: "AWSLambdaDeployer",
            capability: .command(
                intent: .custom(
                    verb: "lambda-deploy",
                    description:
                        "Deploy the Lambda function. You must have an AWS account and know an access key and secret access key."
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

        /// The executable target that implements the three plugins functionality
        .executableTarget(
            name: "AWSLambdaPluginHelper",
            dependencies: [
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOCore", package: "swift-nio"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),

        // remaining targets, unchanged
    ]
)

```

A plugin would be a thin wrapper around the executable target. For example:

```swift
struct AWSLambdaInitializer: CommandPlugin {

    func performCommand(context: PackagePlugin.PluginContext, arguments: [String]) async throws {
        let tool = try context.tool(named: "AWSLambdaPluginHelper")

        let args = ["init", "--dest-dir", context.package.directoryURL.path()] + arguments

        // Invoke the plugin helper on the target directory, passing a configuration
        // file from the package directory.
        let process = try Process.run(tool.url, arguments: args)
        process.waitUntilExit()

        // Check whether the subprocess invocation was successful.
        if !(process.terminationReason == .exit && process.terminationStatus == 0) {
            let problem = "\(process.terminationReason):\(process.terminationStatus)"
            Diagnostics.error("AWSLambdaPluginHelper invocation failed: \(problem)")
        }
    }
}
```

And the executable target would dispatch the invocation to a struct implementing the actual functionality of the plugin:

```swift
    public static func main() async throws {
        let args = CommandLine.arguments
        let helper = AWSLambdaPluginHelper()
        let command = try helper.command(from: args)
        switch command {
        case .`init`:
            try await Initializer().initialize(arguments: args)
        case .build:
            try await Builder().build(arguments: args)
        case .deploy:
            try await Deployer().deploy(arguments: args)
        }
    }
```

## Considered Alternatives

In addition to the proposed solution, we evaluated the following alternatives:

1. **VSCode Extension for Project Scaffolding:**

We considered using a VSCode extension, such as the `vscode-aws-lambda-swift-sam` extension ([https://github.com/swift-server-community/vscode-aws-lambda-swift-sam](https://github.com/swift-server-community/vscode-aws-lambda-swift-sam)), to scaffold new Lambda projects.

This extension creates a new Lambda project from scratch, including the project structure and dependencies. It provides a ready-to-build `main.swift` file with a simple Lambda function and allows users to choose from basic templates, such as "Hello World" or an OpenAPI-based Lambda function. However, the extension relies on the AWS CLI and SAM CLI for deployment. It is only available in the Visual Studio Code Marketplace.

While the extension offers a user-friendly graphical interface, it does not align well with our goals of simplicity for first-time users and minimal dependencies. Users would need to install and configure VSCode, the extension itself, the AWS CLI, and the SAM CLI before getting started.

2. **Deployment DSL with AWS SAM:**

We also considered using a domain-specific language (DSL) to describe deployments, such as the `swift-aws-lambda-sam-dsl` project ([https://github.com/swift-server-community/swift-aws-lambda-sam-dsl](https://github.com/swift-server-community/swift-aws-lambda-sam-dsl)), and leveraging AWS SAM for the actual deployment.

This plugin allows developers to describe their deployment using Swift code, and the plugin automatically generates the corresponding SAM template. However, the plugin depends on the SAM CLI for deployment. Additionally, new developers would need to learn a new DSL for deployment configuration.

We believe the `lambda-deploy` plugin is a preferable alternative because it interacts directly with the AWS REST API and avoids introducing additional dependencies for the user.
