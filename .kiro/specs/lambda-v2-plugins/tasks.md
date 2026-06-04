# Implementation Plan: Lambda V2 Plugins

## Overview

This plan implements the v4 plugin system for `swift-aws-lambda-runtime` following a dependency-aware ordering: foundational Package.swift changes first, then the helper dispatch fix, Builder modifications, vendored code removal, generated AWS clients, the Deployer (the main new piece), documentation migration, and finally tests. Each task builds on prior tasks and ends with integration checkpoints.

## Tasks

- [x] 1. Package.swift changes and foundational setup
  - [x] 1.1 Add soto-core dependency and update AWSLambdaPluginHelper target
    - Add `.package(url: "https://github.com/soto-project/soto-core.git", from: "7.0.0")` to the package dependencies array
    - Add `.product(name: "SotoCore", package: "soto-core")` to the `AWSLambdaPluginHelper` executable target dependencies
    - Verify the existing `AWSLambdaPackager` plugin target (verb: `archive`) is already declared and functional
    - Run `swift package resolve` to confirm dependency resolution succeeds
    - _Requirements: 5.1, 5.2, 7.1_

- [x] 2. Fix helper dispatch bug
  - [x] 2.1 Fix `args.count > 2` guard to `args.count > 1` in AWSLambdaPluginHelper.swift
    - In `command(from:)`, change `guard args.count > 2` to `guard args.count > 1`
    - This unblocks the minimum valid invocation `[binary_path, command]` (count == 2)
    - Verify dispatch still works for `init`, `build`, and `deploy` subcommands
    - _Requirements: 5.4, 5.5 (Design: Helper Dispatch Bug Fix)_

- [x] 3. Builder modifications (minimal changes per Req 10)
  - [x] 3.1 Change default base image to Amazon Linux 2023
    - In `BuilderConfiguration.init`, change the default `baseDockerImage` from `"swift:\(version)-amazonlinux2"` to `"swift:\(version)-amazonlinux2023"`
    - Update the help message default description accordingly
    - _Requirements: 6.1, 2.16_

  - [x] 3.2 Remove blanket AL2 deprecation warning and add targeted AL2 warning
    - Remove the unconditional `displayDeprecationWarning()` call that fires when running on AL2 or when any AL2 image is detected
    - Add a new, shorter informational warning that fires ONLY when `--base-docker-image` explicitly contains `amazonlinux2` but NOT `amazonlinux2023`
    - _Requirements: 6.2, 6.3, 6.4_

  - [x] 3.3 Add default binary stripping with `-Xlinker -s` and `--no-strip` opt-out
    - Add `-Xlinker -s` flags to both native (`buildNative`) and Docker/container (`buildInDocker`) swift build commands
    - Add `--no-strip` flag extraction in `BuilderConfiguration.init`; when present, omit the strip flags
    - _Requirements: 2.5, 2.6_

  - [x] 3.4 Replace `--container-cli` with `--cross-compile` option
    - Replace the `ContainerCLI` enum with a `CrossCompileMethod` enum: `docker`, `container`, `swift-static-sdk`, `custom-sdk`
    - Extract `--cross-compile` option (default: `docker`) instead of `--container-cli`
    - For `swift-static-sdk` and `custom-sdk`, report "not yet supported" error with SDK_Installation_Guide link
    - Retain Docker/container runtime behavior for `docker` and `container` values (reuse existing `ContainerCLI` pull/run logic internally)
    - _Requirements: 2.7, 2.8, 2.9, 2.10, 2.13, 2.14_

  - [x] 3.5 Add `--output-directory` deprecated alias for `--output-path`
    - In `BuilderConfiguration.init`, extract `--output-directory` if `--output-path` is not provided
    - Map it to the same `outputDirectory` property
    - Optionally emit a deprecation notice
    - _Requirements: 7.5, 7.6, 7.7, 7.8_

  - [x] 3.6 Add container CLI existence check with helpful error messages
    - Before executing Docker or container commands, verify the CLI binary exists at the resolved tool path
    - If Docker CLI is missing: report error with Docker download/installation URL
    - If Apple `container` CLI is missing: report error with Apple container CLI download URL
    - _Requirements: 2.11, 2.12_

- [x] 4. Checkpoint - Verify builder compiles and existing tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 5. Remove vendored code
  - [x] 5.1 Delete `Sources/AWSLambdaPluginHelper/Vendored/` directory
    - Remove the entire `Vendored/` directory containing crypto, signer, and HTTP client code
    - Verify the project still compiles (it should, since soto-core replaces this functionality)
    - _Requirements: 5.3_

- [x] 6. Generated AWS service clients
  - [x] 6.1 Create the generation script at `scripts/generate-aws-clients.sh`
    - Write a shell script that clones/uses Soto Code Generator
    - Configure it to produce clients for Lambda, IAM, S3, and STS with only the required operations
    - Script copies output to `Sources/AWSLambdaPluginHelper/GeneratedClients/`
    - Script is maintainer-run, NOT part of the build
    - _Requirements: 4.6, 4.7_

  - [x] 6.2 Create generated Lambda client (`GeneratedClients/Lambda/`)
    - Create `LambdaClient.swift`, `LambdaShapes.swift`, `LambdaErrors.swift`
    - Operations: `CreateFunction`, `UpdateFunctionCode`, `DeleteFunction`, `GetFunction`, `CreateFunctionUrlConfig`, `DeleteFunctionUrlConfig`, `AddPermission`, `RemovePermission`
    - Each operation wraps SotoCore's `AWSClient` with proper request signing
    - _Requirements: 4.1, 4.2_

  - [x] 6.3 Create generated IAM client (`GeneratedClients/IAM/`)
    - Create `IAMClient.swift`, `IAMShapes.swift`, `IAMErrors.swift`
    - Operations: `CreateRole`, `DeleteRole`, `AttachRolePolicy`, `DetachRolePolicy`, `GetRole`, `PutRolePolicy`, `DeleteRolePolicy`
    - _Requirements: 4.1, 4.3_

  - [x] 6.4 Create generated S3 client (`GeneratedClients/S3/`)
    - Create `S3Client.swift`, `S3Shapes.swift`, `S3Errors.swift`
    - Operations: `CreateBucket`, `HeadBucket`, `PutObject`, `DeleteObject`
    - _Requirements: 4.1, 4.4_

  - [x] 6.5 Create generated STS client (`GeneratedClients/STS/`)
    - Create `STSClient.swift`, `STSShapes.swift`, `STSErrors.swift`
    - Operations: `GetCallerIdentity`
    - _Requirements: 4.1, 4.5_

- [x] 7. Checkpoint - Verify generated clients compile with soto-core
  - Ensure all tests pass, ask the user if questions arise.

- [x] 8. Deployer implementation
  - [x] 8.1 Implement `DeployerConfiguration` with full argument parsing
    - Parse: `--help`, `--verbose`, `--with-url`, `--delete`, `--region`, `--iam-role`, `--input-directory`, `--architecture`, `--products`
    - Default architecture to host architecture (`x64` or `arm64`)
    - Default input directory to the standard build output path
    - Update `displayHelpMessage()` with all options
    - _Requirements: 3.3, 3.6, 3.7, 3.9, 3.11, 3.12, 3.13, 3.14, 3.25, 3.26_

  - [x] 8.2 Implement AWS client initialization and credential/config verification
    - Initialize SotoCore `AWSClient` with the credential provider chain
    - Check for `~/.aws/config` and `~/.aws/credentials`; if absent, emit non-blocking informational warning suggesting `aws configure`
    - If credentials cannot be resolved, report descriptive error and fail
    - Handle `--region` override or fall through to Soto's region resolution
    - _Requirements: 3.8, 3.10, 3.21, 3.22, 3.23_

  - [x] 8.3 Implement account ID resolution and function existence check
    - Call STS `GetCallerIdentity` to resolve AWS account ID
    - Call Lambda `GetFunction` to determine if function already exists
    - Determine deployment action: create, update, or delete
    - _Requirements: 3.1, 3.2, 3.16_

  - [x] 8.4 Implement IAM role management
    - When creating a function without `--iam-role`: create IAM role `swift-lambda-<functionName>-role` with Lambda assume-role trust policy
    - Attach `AWSLambdaBasicExecutionRole` managed policy
    - Wait for role propagation before proceeding
    - When `--iam-role` is provided: use the specified role ARN directly
    - When `--delete` is used: detach policies and delete the role
    - _Requirements: 3.4, 3.5, 3.6_

  - [x] 8.5 Implement S3 staging for large archives
    - Define `directUploadLimit = 50 * 1024 * 1024` (50 MB)
    - Implement `deploymentBucketName(region:accountId:)` → `"swift-aws-lambda-runtime-<region>-<accountId>"`
    - If ZIP > 50 MB: check if bucket exists (`HeadBucket`), create if absent (`CreateBucket`)
    - Upload ZIP to bucket (`PutObject`)
    - After deployment, delete the uploaded object (`DeleteObject`) while retaining the bucket
    - _Requirements: 3.15, 3.17, 3.18, 3.19, 3.20_

  - [x] 8.6 Implement create/update/delete function orchestration
    - **Create**: `CreateFunction` with `provided.al2023` runtime, architecture, IAM role, ZIP payload (direct or S3 reference)
    - **Update**: `UpdateFunctionCode` with ZIP payload (direct or S3 reference)
    - **Delete**: `DeleteFunction`, then delete IAM role and its policies
    - Report AWS errors with service, operation, and message
    - _Requirements: 3.1, 3.2, 3.4, 3.24, 6.5_

  - [x] 8.7 Implement Function URL setup
    - When `--with-url` is provided: call `CreateFunctionUrlConfig` with `AWS_IAM` auth type
    - Add resource-based permission for Function URL invocation
    - _Requirements: 3.7_

  - [x] 8.8 Implement post-deploy output (success reporting)
    - Report Lambda function ARN and deployment region
    - If `--with-url`: display Function URL and a ready-to-use `curl --aws-sigv4` command
    - If no URL: display a ready-to-use `aws lambda invoke` command
    - Shutdown AWSClient cleanly
    - _Requirements: 3.27, 3.28, 3.29_

- [x] 9. Checkpoint - Verify deployer compiles and integrates with generated clients
  - Ensure all tests pass, ask the user if questions arise.

- [x] 10. Documentation migration
  - [x] 10.1 Update DocC articles and tutorials
    - Update articles under `Sources/AWSLambdaRuntime/Docs.docc/` to show `lambda-init`, `lambda-build`, `lambda-deploy` commands
    - Replace `swift package archive` references with `swift package lambda-build`
    - Replace raw AWS CLI deployment commands with `lambda-deploy` plugin usage (except SAM/CDK examples)
    - Remove obsolete Amazon Linux 2 deprecation guidance
    - Document `aws configure` prerequisite for local deployments
    - _Requirements: 8.1, 8.2, 8.3, 8.5, 8.7_

  - [x] 10.2 Update top-level readme.md and example READMEs
    - Update `readme.md` with new plugin commands and workflow
    - Update example READMEs under `Examples/` to show new commands
    - Keep SAM/CDK examples using their respective deployment tools
    - May retain `aws lambda invoke` for invocation examples
    - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.6_

- [x] 11. Unit tests
  - [x] 11.1 Write unit tests for BuilderConfiguration argument parsing
    - Test `--cross-compile` parsing with all valid values and invalid values
    - Test `--no-strip` flag detection
    - Test `--output-directory` deprecated alias maps to `outputDirectory`
    - Test mutual exclusion of `--swift-version` and `--base-docker-image`
    - Test default base image is `amazonlinux2023`
    - _Requirements: 2.5, 2.6, 2.7, 2.17, 6.1, 7.5_

  - [x] 11.2 Write unit tests for DeployerConfiguration argument parsing
    - Test `--architecture` parsing with valid and invalid values
    - Test default architecture matches host
    - Test `--region`, `--iam-role`, `--input-directory`, `--with-url`, `--delete` parsing
    - Test `--help` flag produces help output without AWS calls
    - _Requirements: 3.13, 3.14, 3.25_

  - [x] 11.3 Write unit tests for deployment bucket name construction and archive threshold
    - Test `deploymentBucketName(region:accountId:)` produces correct format
    - Test bucket name is valid S3 name (lowercase, 3-63 chars)
    - Test `directUploadLimit` boundary: exactly 50 MB → direct, 50 MB + 1 → S3
    - _Requirements: 3.15, 3.17, 3.19_

  - [x] 11.4 Write property test for deprecated option alias equivalence (Property 2)
    - **Property 2: Deprecated option alias equivalence**
    - For any path value, `--output-directory <path>` produces the same `outputDirectory` as `--output-path <path>`
    - **Validates: Requirements 7.5, 7.6**

  - [x] 11.5 Write property test for cross-compile method parsing round-trip (Property 3)
    - **Property 3: Cross-compile method parsing round-trip**
    - For any valid `CrossCompileMethod` case, `rawValue` → parse → original case
    - **Validates: Requirements 2.7**

  - [x] 11.6 Write property test for mutual exclusion of --swift-version and --base-docker-image (Property 4)
    - **Property 4: Mutual exclusion of --swift-version and --base-docker-image**
    - For any non-empty swift-version and any non-empty base-docker-image, parsing throws an error
    - **Validates: Requirements 2.17**

  - [x] 11.7 Write property test for deployment bucket name construction (Property 5)
    - **Property 5: Deployment bucket name construction**
    - For any valid region and 12-digit account ID, result matches `"swift-aws-lambda-runtime-<region>-<accountId>"` and is a valid S3 bucket name
    - **Validates: Requirements 3.17, 3.18**

  - [x] 11.8 Write property test for archive size determines upload strategy (Property 6)
    - **Property 6: Archive size determines upload strategy**
    - For any size ≤ 50 MB → direct upload chosen; for any size > 50 MB → S3 staging chosen
    - **Validates: Requirements 3.15, 3.19**

  - [x] 11.9 Write property test for AL2 warning logic (Property 8)
    - **Property 8: AL2 warning emitted only for explicit AL2 image selection**
    - For any image string containing "amazonlinux2" but NOT "amazonlinux2023" → warning emitted; for "amazonlinux2023" or default → no warning
    - **Validates: Requirements 6.2, 6.3**

  - [x] 11.10 Write property test for unsupported cross-compile methods (Property 9)
    - **Property 9: Unsupported cross-compile methods report error with link**
    - For `swift-static-sdk` and `custom-sdk`, builder reports "not yet supported" error containing SDK guide URL
    - **Validates: Requirements 2.14**

- [x] 12. Checkpoint - Ensure all unit and property tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 13. End-to-end test script
  - [x] 13.1 Create `scripts/integration-test.sh` shell script
    - Implement the full lifecycle: scaffold (lambda-init --with-url) → build (lambda-build) → deploy (lambda-deploy --with-url) → validate (curl --aws-sigv4 to Function URL) → delete (lambda-deploy --delete)
    - Use `trap cleanup EXIT` to guarantee resource cleanup on failure
    - Verify response body matches expected output
    - Use unique function name with timestamp to avoid conflicts
    - Script must be `bash`, NOT Swift
    - _Requirements: 9.1, 9.2, 9.3, 9.4, 9.5, 9.6, 9.7, 9.8, 9.9, 9.10, 9.11_

- [x] 14. Final checkpoint - Full build verification
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- Property tests validate universal correctness properties from the design document
- Unit tests validate specific examples and edge cases
- The Deployer (task 8) is the largest piece of new work and is broken into focused sub-tasks
- Builder modifications (task 3) are minimal per Requirement 10 (preserve existing working code)
- Generated clients (task 6) must be in place before the Deployer can compile
- Documentation and tests can proceed in parallel once core implementation is complete
- The e2e test (task 13) depends on all prior implementation being complete

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1"] },
    { "id": 1, "tasks": ["2.1", "5.1"] },
    { "id": 2, "tasks": ["3.1", "3.2", "3.3", "3.4", "3.5", "3.6"] },
    { "id": 3, "tasks": ["6.1"] },
    { "id": 4, "tasks": ["6.2", "6.3", "6.4", "6.5"] },
    { "id": 5, "tasks": ["8.1"] },
    { "id": 6, "tasks": ["8.2", "8.3"] },
    { "id": 7, "tasks": ["8.4", "8.5"] },
    { "id": 8, "tasks": ["8.6"] },
    { "id": 9, "tasks": ["8.7", "8.8"] },
    { "id": 10, "tasks": ["10.1", "10.2", "11.1", "11.2", "11.3"] },
    { "id": 11, "tasks": ["11.4", "11.5", "11.6", "11.7", "11.8", "11.9", "11.10"] },
    { "id": 12, "tasks": ["13.1"] }
  ]
}
```
