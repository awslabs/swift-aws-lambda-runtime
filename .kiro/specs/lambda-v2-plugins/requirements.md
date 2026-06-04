# Requirements Document

## Introduction

This feature delivers the v4 plugin system for `swift-aws-lambda-runtime`, replacing the legacy single-purpose `archive` plugin with three focused SwiftPM command plugins that cover the end-to-end developer experience: scaffolding (`lambda-init`), building and packaging (`lambda-build`), and deployment (`lambda-deploy`). The authoritative design source is the v4 proposal (`Plugins/Documentation.docc/Proposals/0001-v4-plugins.md`).

The three plugins are thin `CommandPlugin` wrappers (`AWSLambdaInitializer`, `AWSLambdaBuilder`, `AWSLambdaDeployer`) that spawn a shared executable target (`AWSLambdaPluginHelper`) which implements the actual `init`, `build`, and `deploy` logic. The v4 proposal changes the deployment strategy to depend on Soto Core for AWS credential management, configuration parsing, and request signing, with AWS service clients generated one-time by the Soto Code Generator and checked into the repository. Vendored crypto, signer, and HTTP client code is removed.

This release makes Amazon Linux 2023 the default Amazon Linux target and the default base container image (`swift:<version>-amazonlinux2023`), with the associated default Lambda runtime `provided.al2023`. Amazon Linux 2 (AL2) is no longer the default but remains usable when the developer explicitly supplies an AL2 base image through the `--base-docker-image` option. The Amazon Linux 2 deprecation warning is removed.

The project targets Swift 6 with Swift Package Manager, is developed on macOS 15 or later, and targets the Amazon Linux 2023 (`provided.al2023`) Lambda runtime.

## Glossary

- **Plugin_System**: The collective set of three SwiftPM command plugins (`AWSLambdaInitializer`, `AWSLambdaBuilder`, `AWSLambdaDeployer`) and the shared `AWSLambdaPluginHelper` executable target.
- **Plugin_Helper**: The `AWSLambdaPluginHelper` executable target that implements the `init`, `build`, and `deploy` commands and is invoked as a subprocess by each plugin wrapper.
- **Init_Plugin**: The `lambda-init` command (wrapper `AWSLambdaInitializer`) that scaffolds a new Lambda function source file.
- **Build_Plugin**: The `lambda-build` command (wrapper `AWSLambdaBuilder`) that compiles and packages a Lambda function into a deployable ZIP archive.
- **Deploy_Plugin**: The `lambda-deploy` command (wrapper `AWSLambdaDeployer`) that deploys a packaged Lambda function to AWS.
- **Template**: A hardcoded Swift source file scaffolded by the Init_Plugin into `Sources/main.swift`.
- **Default_Template**: The Template that defines a Lambda function receiving a JSON request and returning a JSON response.
- **URL_Template**: The Template that defines a Lambda function invoked through a Lambda Function URL using `FunctionURLRequest` and `FunctionURLResponse`.
- **ZIP_Archive**: The deployment package produced by the Build_Plugin containing the compiled binary renamed to `bootstrap` plus any `.resources` bundles.
- **Cross_Compilation_Method**: The mechanism used to compile a Lambda binary for Amazon Linux 2023 when the build does not run natively on Amazon_Linux_2023. Accepted values are `docker` (cross-compile using Docker), `container` (cross-compile using Apple's `container` CLI, a native OCI image runtime for macOS that does not require Docker Desktop), `swift-static-sdk` (the Swift Static Linux SDK built with musl), and `custom-sdk` (a custom Swift SDK for Amazon Linux).
- **SDK_Installation_Guide**: The published documentation website that explains how to install the Swift Static Linux SDK and the custom Swift SDK for Amazon Linux used by the `swift-static-sdk` and `custom-sdk` Cross_Compilation_Method values.
- **Amazon_Linux_2023**: The Amazon Linux 2023 operating system, used as the default cross-compilation target environment and corresponding to the `provided.al2023` Lambda runtime.
- **Base_Image**: The container image used for Docker-based cross-compilation, defaulting to `swift:<version>-amazonlinux2023` and overridable by the developer through the `--base-docker-image` option.
- **Lambda_Runtime_Identifier**: The default AWS Lambda managed runtime identifier `provided.al2023` used when deploying functions.
- **Soto_Core**: The `soto-core` Swift package providing AWS credential management, configuration file parsing, SigV4 request signing, and HTTP client functionality.
- **Credential_Provider_Chain**: Soto Core's ordered credential resolution: environment variables (including the `AWS_PROFILE` environment variable), AWS configuration files (`~/.aws/credentials` and `~/.aws/config`), ECS container credentials, and EC2 instance metadata service (IMDSv2). Soto Core resolves the active region from the same environment variables and AWS profile configuration.
- **AWS_Configuration_Resolution**: Soto_Core's standard resolution of the AWS region, credentials, and active profile from the environment variables (`AWS_REGION`, `AWS_DEFAULT_REGION`, and `AWS_PROFILE`) and the AWS configuration files (`~/.aws/config` and `~/.aws/credentials`), used instead of any plugin-specific configuration parsing.
- **AWS_Configuration_Files**: The `~/.aws/config` and `~/.aws/credentials` files created by running the AWS CLI `aws configure` command, which store the developer's AWS credentials and default region and are consumed by AWS_Configuration_Resolution and the Credential_Provider_Chain.
- **Generated_Service_Client**: AWS service API client code (Lambda, IAM, S3, and STS) produced one time by the maintainer-run Generation_Script using the Soto Code Generator and committed to the repository, not generated at build time.
- **Generation_Script**: A maintainer-invoked script that runs the Soto Code Generator one time to produce the Generated_Service_Client source code, which is then committed to the repository. The Generation_Script is a manual operation and is not part of the package build.
- **Deployment_Bucket**: The dedicated, reusable Amazon S3 bucket named `swift-aws-lambda-runtime-<region>-<account-number>` used to stage large deployment ZIP_Archive uploads, where `<region>` is the deployment region and `<account-number>` is the AWS_Account_Identifier. The Deployment_Bucket is created when absent and reused when present.
- **AWS_Account_Identifier**: The AWS account number, resolved through the AWS STS `GetCallerIdentity` API, used as part of the Deployment_Bucket name.
- **Function_Name**: The Lambda function name, derived from the `executableTarget` name defined in `Package.swift`.
- **Function_URL**: An HTTPS endpoint that invokes a Lambda function directly, configured through the AWS Lambda `CreateFunctionUrlConfig` API. The Function_URL uses IAM (`AWS_IAM`) authentication, so callers must sign their requests with AWS Signature Version 4 rather than calling the endpoint anonymously.
- **IAM_Role**: The AWS Identity and Access Management role assumed by the deployed Lambda function during execution.
- **Host_Architecture**: The CPU architecture of the machine on which the Deploy_Plugin runs, expressed as `x64` or `arm64`.
- **Legacy_Archive_Plugin**: The existing `archive` SwiftPM command plugin (verb `archive`) provided before the v4 plugin system, which this release retains as a passthrough to the Build_Plugin.
- **Deprecated_Option_Alias**: A Legacy_Archive_Plugin option name (such as `--output-directory`) that the Build_Plugin still accepts and maps to its current replacement option name (such as `--output-path`), supported for backward compatibility but not the primary documented interface.
- **End_To_End_Test_Suite**: The automated test, implemented as a shell script, that scaffolds, builds, deploys, validates, and deletes a Lambda function to validate the full plugin lifecycle end to end against AWS. The suite uses the URL function variant (the URL_Template) and validates the deployed function by sending an AWS Signature Version 4 signed `curl` request to its IAM-protected Function_URL.

## Requirements

### Requirement 1: Scaffold a new Lambda function (lambda-init)

**User Story:** As a Swift developer new to AWS Lambda, I want to scaffold a ready-to-build Lambda function from a template, so that I can start a new project without writing boilerplate by hand.

#### Acceptance Criteria

1. WHEN the Init_Plugin is invoked without a template option, THE Plugin_Helper SHALL write the Default_Template to `Sources/main.swift`.
2. WHEN the Init_Plugin is invoked with the `--with-url` option, THE Plugin_Helper SHALL write the URL_Template to `Sources/main.swift`.
3. THE Default_Template SHALL define a Lambda function that decodes a JSON request into a `Decodable` type and returns an `Encodable` JSON response.
4. THE URL_Template SHALL define a Lambda function that accepts a `FunctionURLRequest` and returns a `FunctionURLResponse`.
5. WHERE the `--allow-writing-to-package-directory` option is provided, THE Init_Plugin SHALL write to the package directory without requesting interactive permission.
6. WHEN the Init_Plugin is invoked with the `--verbose` option, THE Plugin_Helper SHALL emit the destination path of the created file.
7. WHEN the Init_Plugin is invoked with the `--help` option, THE Plugin_Helper SHALL display usage information and SHALL NOT write any file.
8. IF writing the Template to `Sources/main.swift` fails, THEN THE Plugin_Helper SHALL report a descriptive error identifying the failure.
9. WHEN the Init_Plugin completes successfully, THE Plugin_Helper SHALL report the path of the created file and the next command to package the function.

### Requirement 2: Build and package the Lambda function (lambda-build)

**User Story:** As a Lambda developer, I want to compile my function for Amazon Linux 2023 and package it as a deployment ZIP, so that I can upload an artifact that runs on AWS Lambda.

#### Acceptance Criteria

1. WHEN the Build_Plugin is invoked on Amazon_Linux_2023, THE Plugin_Helper SHALL compile the configured products natively using `swift build` with the `--static-swift-stdlib` flag.
2. WHILE running on a platform other than Amazon_Linux_2023, THE Plugin_Helper SHALL compile the configured products using the selected Cross_Compilation_Method.
3. WHEN packaging a compiled product, THE Plugin_Helper SHALL produce a ZIP_Archive containing the product binary renamed to `bootstrap`.
4. WHEN packaging a compiled product that has associated `.resources` bundles, THE Plugin_Helper SHALL include each `.resources` bundle in the ZIP_Archive.
5. WHEN compiling a product, THE Plugin_Helper SHALL pass the linker flags `-Xlinker -s` to strip debug symbols from the binary.
6. WHERE the `--no-strip` option is provided, THE Plugin_Helper SHALL compile the product without the debug-symbol-stripping linker flags.
7. THE Build_Plugin SHALL accept a `--cross-compile` option that selects the Cross_Compilation_Method from the values `docker`, `container`, `swift-static-sdk`, and `custom-sdk`, defaulting to `docker`.
8. WHEN the `--cross-compile` option is omitted, THE Plugin_Helper SHALL use the `docker` Cross_Compilation_Method.
9. WHERE the Cross_Compilation_Method is `docker`, THE Plugin_Helper SHALL execute the compilation in a container started with Docker.
10. WHERE the Cross_Compilation_Method is `container`, THE Plugin_Helper SHALL execute the compilation in a container started with Apple's `container` CLI.
11. IF the Cross_Compilation_Method is `docker` and the Docker CLI cannot be located, THEN THE Plugin_Helper SHALL report that Docker is not installed and SHALL direct the user to the Docker download and installation page.
12. IF the Cross_Compilation_Method is `container` and Apple's `container` CLI cannot be located, THEN THE Plugin_Helper SHALL report that the `container` CLI is not installed and SHALL direct the user to the Apple `container` CLI download and installation page.
13. THE Plugin_Helper SHALL support the `docker` and `container` Cross_Compilation_Method values.
14. WHEN the `--cross-compile` option selects `swift-static-sdk` or `custom-sdk`, THE Plugin_Helper SHALL report that the selected Cross_Compilation_Method is not yet supported and SHALL direct the user to the SDK_Installation_Guide describing how to install the corresponding SDK.
15. WHEN the Cross_Compilation_Method is `container`, THE Plugin_Helper SHALL pull the Base_Image and run the build using the image-pull and run command forms appropriate to the Apple `container` CLI.
16. WHEN the `--base-docker-image` option is omitted, THE Plugin_Helper SHALL use `swift:<version>-amazonlinux2023` as the Base_Image.
17. IF both the `--swift-version` option and the `--base-docker-image` option are provided, THEN THE Plugin_Helper SHALL report a mutually-exclusive-argument error.
18. WHEN the `--disable-docker-image-update` option is omitted and the Cross_Compilation_Method is `docker` or `container`, THE Plugin_Helper SHALL pull the Base_Image before compiling.
19. WHERE the `--disable-docker-image-update` option is provided, THE Plugin_Helper SHALL compile without pulling the Base_Image.
20. THE Build_Plugin SHALL accept the options `--output-path`, `--products`, `--configuration`, `--swift-version`, `--verbose`, and `--help` with the same meaning as the existing `archive` plugin.
21. WHEN the `--configuration` option is omitted, THE Plugin_Helper SHALL build using the `release` configuration.
22. IF a configured product binary is absent after compilation, THEN THE Plugin_Helper SHALL report that the product executable was not found.
23. WHEN the Build_Plugin completes successfully, THE Plugin_Helper SHALL report the count of created archives and the path of each ZIP_Archive.

### Requirement 3: Deploy the Lambda function to AWS (lambda-deploy)

**User Story:** As a Lambda developer, I want to deploy my packaged function to AWS from the command line, so that I can run my function in the cloud without configuring separate deployment tooling.

#### Acceptance Criteria

1. WHEN the Deploy_Plugin is invoked and no Lambda function with the Function_Name exists, THE Plugin_Helper SHALL create the function using the AWS Lambda `CreateFunction` API with the `provided.al2023` Lambda_Runtime_Identifier.
2. WHEN the Deploy_Plugin is invoked and a Lambda function with the Function_Name already exists, THE Plugin_Helper SHALL update the function code using the AWS Lambda `UpdateFunctionCode` API.
3. THE Plugin_Helper SHALL determine the Function_Name from the `executableTarget` name defined in `Package.swift`.
4. WHEN the Deploy_Plugin is invoked with the `--delete` option, THE Plugin_Helper SHALL delete the Lambda function using the `DeleteFunction` API and delete its associated IAM_Role.
5. WHEN the Deploy_Plugin creates a Lambda function and no `--iam-role` option is provided, THE Plugin_Helper SHALL create a new IAM_Role with the permissions required for Lambda execution.
6. WHERE the `--iam-role` option is provided, THE Plugin_Helper SHALL configure the Lambda function to use the specified IAM_Role.
7. WHERE the `--with-url` option is provided, THE Plugin_Helper SHALL configure a Function_URL using the `CreateFunctionUrlConfig` API with the `AWS_IAM` auth type, so that the Function_URL is protected by IAM authentication and callers must sign requests with AWS Signature Version 4 rather than being granted public, unauthenticated access.
8. WHEN the `--region` option is omitted, THE Plugin_Helper SHALL deploy to the AWS region resolved through AWS_Configuration_Resolution provided by Soto_Core.
9. WHERE the `--region` option is provided, THE Plugin_Helper SHALL deploy to the specified region, overriding the region resolved through AWS_Configuration_Resolution.
10. THE Plugin_Helper SHALL respect the current AWS region, credentials, and profile selection through Soto_Core's AWS_Configuration_Resolution rather than implementing its own configuration parsing.
11. WHEN the `--input-directory` option is omitted, THE Plugin_Helper SHALL read the deployment ZIP_Archive from the default Build_Plugin output path.
12. WHERE the `--input-directory` option is provided, THE Plugin_Helper SHALL read the deployment ZIP_Archive from the specified path.
13. WHEN the `--architecture` option is omitted, THE Plugin_Helper SHALL set the function architecture to the Host_Architecture.
14. WHERE the `--architecture` option is provided with `x64` or `arm64`, THE Plugin_Helper SHALL set the function architecture to the specified value.
15. WHEN the deployment ZIP_Archive size is within the AWS Lambda direct-upload limit, THE Plugin_Helper SHALL deploy the function code as a Base64 payload through the AWS Lambda REST API.
16. THE Plugin_Helper SHALL determine the AWS_Account_Identifier through the AWS STS `GetCallerIdentity` API.
17. WHEN the deployment ZIP_Archive size exceeds the AWS Lambda direct-upload limit AND the Deployment_Bucket does not exist, THE Plugin_Helper SHALL create the Deployment_Bucket named `swift-aws-lambda-runtime-<region>-<account-number>` using the `CreateBucket` API.
18. WHEN the deployment ZIP_Archive size exceeds the AWS Lambda direct-upload limit AND the Deployment_Bucket already exists, THE Plugin_Helper SHALL reuse the Deployment_Bucket without recreating it.
19. WHEN the deployment ZIP_Archive size exceeds the AWS Lambda direct-upload limit, THE Plugin_Helper SHALL upload the ZIP_Archive as an S3 object into the Deployment_Bucket using the `PutObject` API and reference that object during deployment.
20. WHEN the deployment completes, THE Plugin_Helper SHALL delete the uploaded S3 object from the Deployment_Bucket using the `DeleteObject` API while retaining the Deployment_Bucket for reuse.
21. THE Plugin_Helper SHALL resolve AWS credentials using the Credential_Provider_Chain.
22. IF AWS credentials cannot be resolved through the Credential_Provider_Chain, THEN THE Plugin_Helper SHALL report a descriptive credential-resolution error and SHALL fail the deployment.
23. WHEN the Deploy_Plugin runs and the local AWS_Configuration_Files (`~/.aws/config` and `~/.aws/credentials`) are absent, THE Plugin_Helper SHALL emit a non-blocking, informational warning that suggests installing the AWS CLI and running `aws configure`, and SHALL continue the deployment, because credentials may still be resolved from environment variables, ECS or EKS container credentials, or the EC2 instance metadata service (IMDSv2) through the Credential_Provider_Chain; the absence of the local AWS_Configuration_Files alone SHALL NOT block deployment, and the deployment fails only when credentials cannot be resolved through the Credential_Provider_Chain (criterion 3.22) or when an AWS API request returns an error response (criterion 3.24).
24. IF an AWS API request returns an error response, THEN THE Plugin_Helper SHALL report the AWS error to the developer.
25. WHEN the Deploy_Plugin is invoked with the `--help` option, THE Plugin_Helper SHALL display usage information and SHALL NOT call any AWS API.
26. WHEN the Deploy_Plugin is invoked with the `--verbose` option, THE Plugin_Helper SHALL emit detailed progress output for each AWS API interaction.
27. WHEN the Deploy_Plugin completes a successful deployment, THE Plugin_Helper SHALL report the Lambda function ARN and the deployment region to the developer.
28. WHERE the `--with-url` option is provided and the deployment completes successfully, THE Plugin_Helper SHALL report the Function_URL to the developer and SHALL display a ready-to-use `curl` command that includes AWS Signature Version 4 authentication (using curl's `--aws-sigv4` option) so the developer can immediately invoke the function.
29. WHERE the `--with-url` option is not provided and the deployment completes successfully, THE Plugin_Helper SHALL display a ready-to-use `aws lambda invoke` command that the developer can use to invoke the deployed function.

### Requirement 4: AWS service client generation and access

**User Story:** As a project maintainer, I want type-safe AWS service clients for Lambda, IAM, S3, and STS generated once and checked into the repository, so that the deploy plugin can call AWS APIs without depending on the entire Soto SDK at build time.

#### Acceptance Criteria

1. THE Plugin_System SHALL include Generated_Service_Client code for the AWS Lambda, IAM, S3, and STS operations required by the Deploy_Plugin, committed to the repository.
2. THE Generated_Service_Client for AWS Lambda SHALL provide the operations `CreateFunction`, `UpdateFunctionCode`, `DeleteFunction`, `GetFunction`, `CreateFunctionUrlConfig`, `DeleteFunctionUrlConfig`, `AddPermission`, and `RemovePermission`.
3. THE Generated_Service_Client for AWS IAM SHALL provide the operations `CreateRole`, `DeleteRole`, `AttachRolePolicy`, `DetachRolePolicy`, `GetRole`, `PutRolePolicy`, and `DeleteRolePolicy`.
4. THE Generated_Service_Client for AWS S3 SHALL provide the operations `CreateBucket`, `HeadBucket`, `PutObject`, and `DeleteObject`.
5. THE Generated_Service_Client for AWS STS SHALL provide the operation `GetCallerIdentity`.
6. THE Plugin_System SHALL provide a Generation_Script that invokes the Soto Code Generator to produce the Generated_Service_Client code for the required AWS Lambda, IAM, S3, and STS operations.
7. THE Generation_Script SHALL be a one-time, maintainer-run operation that is separate from the package build.
8. THE Plugin_System SHALL commit the Generated_Service_Client source code produced by the Generation_Script to the git repository.
9. WHEN a developer builds the package, THE Plugin_System SHALL compile the Generated_Service_Client code present on the file system, SHALL NOT invoke the Soto Code Generator during the build, and SHALL fail the build if the Generated_Service_Client code is not found on the file system.

### Requirement 5: Dependencies and package integration

**User Story:** As a project maintainer, I want the package to depend on Soto Core and remove vendored AWS infrastructure code, so that credential handling and request signing are production-tested and the maintenance burden is reduced.

#### Acceptance Criteria

1. THE Plugin_System SHALL declare a package dependency on `soto-core`.
2. THE Plugin_Helper target SHALL depend on the `SotoCore` product.
3. THE Plugin_System SHALL NOT include vendored crypto, signer, or HTTP client code under `Sources/AWSLambdaPluginHelper/Vendored/`.
4. THE Plugin_System SHALL implement the `init`, `build`, and `deploy` commands within the single `AWSLambdaPluginHelper` executable target.
5. WHEN a plugin wrapper is invoked, THE plugin wrapper SHALL run the Plugin_Helper as a subprocess and pass the corresponding command and arguments.
6. IF the Plugin_Helper subprocess exits with a non-zero status, THEN THE invoking plugin wrapper SHALL report a diagnostic error and SHALL halt immediately without continuing further work.

### Requirement 6: Amazon Linux 2023 as the default target

**User Story:** As a Lambda developer, I want Amazon Linux 2023 to be the default target, so that my functions build and deploy against the current, supported AWS Lambda runtime without legacy AL2 prompts, while I retain the ability to target Amazon Linux 2 when I explicitly need it.

#### Acceptance Criteria

1. THE Build_Plugin SHALL use `swift:<version>-amazonlinux2023` as the default Base_Image.
2. THE Plugin_System SHALL NOT emit an Amazon Linux 2 deprecation warning when the developer does not explicitly select an Amazon Linux 2 base image.
3. WHERE the developer explicitly provides an Amazon Linux 2 image through the `--base-docker-image` option, THE Plugin_Helper SHALL emit an informational warning noting that Amazon Linux 2 is deprecated and recommending migration to Amazon Linux 2023.
4. WHERE the developer provides an Amazon Linux 2 image through the `--base-docker-image` option, THE Plugin_Helper SHALL compile the products using the supplied Base_Image.
5. WHEN the Deploy_Plugin creates or updates a Lambda function, THE Plugin_Helper SHALL set the Lambda_Runtime_Identifier to `provided.al2023` as the default runtime.
6. WHEN the Build_Plugin runs natively on Amazon_Linux_2023, THE Plugin_Helper SHALL compile the products without requiring a container runtime.

### Requirement 7: Backward compatibility with the legacy `archive` plugin

**User Story:** As a developer with existing CI pipelines that call `swift package archive`, I want the legacy `archive` command to keep working as a passthrough to the new build plugin with an unchanged CLI, so that upgrading to the v4 plugin system does not break my existing automation.

#### Acceptance Criteria

1. THE Plugin_System SHALL retain an `archive` command that acts as a passthrough to the Build_Plugin, resolving to the same sources and implementation as the `lambda-build` command.
2. WHEN a developer invokes `swift package archive`, THE Plugin_System SHALL perform the same build-and-package behavior as `swift package lambda-build`.
3. WHEN a developer invokes the `archive` command, THE Plugin_System SHALL display a deprecation warning that encourages the developer to use the `lambda-build` plugin (the `swift package lambda-build` command) instead, while still performing the build-and-package work.
4. THE Build_Plugin SHALL accept the command-line interface of the Legacy_Archive_Plugin, including the options `--output-directory`, `--products`, `--configuration`, `--swift-version`, `--base-docker-image`, `--disable-docker-image-update`, `--verbose`, and `--help`, so that existing invocations continue to work unchanged.
5. THE Build_Plugin SHALL accept the legacy `--output-directory` option as a Deprecated_Option_Alias for `--output-path`.
6. WHEN a developer supplies a Deprecated_Option_Alias such as `--output-directory`, THE Plugin_Helper SHALL treat the Deprecated_Option_Alias as equivalent to its current replacement option such as `--output-path`.
7. WHERE an option name has been renamed from the Legacy_Archive_Plugin, THE Build_Plugin SHALL accept the legacy option name as a Deprecated_Option_Alias that maps to the current option name.
8. WHEN a developer supplies a Deprecated_Option_Alias, THE Plugin_Helper MAY emit a deprecation notice indicating the current option name and SHALL honor the Deprecated_Option_Alias.
9. THE documentation for the Build_Plugin SHALL document the current option names as the primary documented interface and SHALL present the Deprecated_Option_Alias names only as supported compatibility aliases.
10. THE Plugin_System SHALL accept a set of Build_Plugin options that is a superset of the Legacy_Archive_Plugin options so that existing CI invocations of `swift package archive` continue to work.

### Requirement 8: Documentation, tutorials, and examples migration

**User Story:** As a developer learning from the project's documentation and examples, I want all DocC documentation, tutorials, and example READMEs updated to show the new plugin usage, so that I follow the current recommended workflow instead of deprecated commands.

#### Acceptance Criteria

1. THE Plugin_System documentation SHALL update the DocC articles and tutorials under `Sources/AWSLambdaRuntime/Docs.docc/`, the top-level `readme.md`, and the example READMEs under `Examples/` to show the new plugin commands `lambda-init`, `lambda-build`, and `lambda-deploy`.
2. WHERE documentation or an example README currently shows `swift package archive`, THE documentation SHALL show `swift package lambda-build` using the current option names.
3. WHERE an example currently deploys using the raw AWS CLI commands such as `aws lambda create-function`, `aws lambda update-function-code`, or `aws lambda create-function-url-config`, THE example documentation SHALL show the `lambda-deploy` plugin instead.
4. WHERE an example currently deploys using AWS SAM with a `template.yaml` and `sam deploy` or using AWS CDK with `cdk deploy`, THE example SHALL continue to use AWS SAM or AWS CDK respectively and SHALL retain its existing deployment tooling rather than the `lambda-deploy` plugin.
5. THE documentation SHALL remove the references to the Amazon Linux 2 deprecation guidance that are made obsolete by Requirement 6, consistent with Amazon_Linux_2023 being the default target.
6. WHERE example documentation shows invoking the function, THE example documentation MAY retain the raw `aws lambda invoke` command for invocation, because this release provides no plugin invoke command.
7. THE documentation SHALL describe, as a prerequisite for local developer-machine deployments with the Deploy_Plugin, that the developer install the AWS CLI and run `aws configure` to create the AWS configuration in `~/.aws`, and SHALL note that on EC2, ECS, or EKS the credentials are typically provided automatically by the instance or task role through the Credential_Provider_Chain, so running `aws configure` is not required in those environments.

### Requirement 9: End-to-end lifecycle test suite

**User Story:** As a project maintainer, I want an automated end-to-end test that exercises the full plugin lifecycle (scaffold → build → deploy → invoke → delete), so that I can verify the three plugins work together against real AWS before release.

#### Acceptance Criteria

1. THE Plugin_System SHALL provide an End_To_End_Test_Suite that exercises the full lifecycle: scaffold using the Init_Plugin with the URL_Template, build and package using the Build_Plugin, deploy using the Deploy_Plugin with the `--with-url` option, validate the deployed function through its Function_URL, and delete using the Deploy_Plugin with the `--delete` option.
2. THE End_To_End_Test_Suite SHALL be implemented as a shell script and SHALL NOT be implemented as Swift code.
3. WHEN the End_To_End_Test_Suite runs, THE End_To_End_Test_Suite SHALL scaffold a new Lambda function using the Init_Plugin with the URL_Template through the `--with-url` option.
4. WHEN the function has been scaffolded, THE End_To_End_Test_Suite SHALL build and package the function using the Build_Plugin.
5. WHEN the function has been packaged, THE End_To_End_Test_Suite SHALL deploy the function to AWS using the Deploy_Plugin with the `--with-url` option so that a Function_URL is configured.
6. WHEN the function has been deployed, THE End_To_End_Test_Suite SHALL validate the deployment by sending an HTTP request to the Function_URL using a `curl` command and SHALL verify the returned response.
7. THE Function_URL created by the End_To_End_Test_Suite SHALL use IAM authentication (the `AWS_IAM` auth type) rather than public, unauthenticated access.
8. WHEN the End_To_End_Test_Suite invokes the Function_URL with `curl`, THE End_To_End_Test_Suite SHALL sign the request using AWS Signature Version 4 via curl's built-in `--aws-sigv4` option.
9. WHEN the validation completes, THE End_To_End_Test_Suite SHALL delete the deployed Lambda function and its associated IAM_Role using the Deploy_Plugin `--delete` option.
10. IF any step of the End_To_End_Test_Suite fails after the function has been deployed, THEN THE End_To_End_Test_Suite SHALL delete the deployed Lambda function and its associated resources so that no AWS resources are leaked.
11. IF the Function_URL response does not match the expected result, THEN THE End_To_End_Test_Suite SHALL report a test failure.

### Requirement 10: Preserve existing working implementation

**User Story:** As a project maintainer, I want the existing partially-implemented init and build code to be preferred over newly generated code, so that proven working behavior is not regressed by a rewrite.

#### Acceptance Criteria

1. WHERE an existing implementation of the Init_Plugin or Build_Plugin functionality is present in the repository, THE Plugin_System SHALL reuse the existing implementation rather than replacing it with newly generated code.
2. THE Plugin_System SHALL preserve the existing behavior of the Init_Plugin and Build_Plugin except where a change is required to satisfy an acceptance criterion in this specification.
3. IF existing Init_Plugin or Build_Plugin code is proven incorrect by failing an acceptance criterion or a test, THEN THE Plugin_System SHALL modify or replace only the incorrect code.
4. WHEN modifying the existing Init_Plugin or Build_Plugin code to satisfy the new requirements, including default-symbol stripping, the Amazon Linux 2023 default Base_Image, or the unified `--cross-compile` option, THE Plugin_System SHALL make the minimal changes necessary and SHALL retain the remaining working behavior.
