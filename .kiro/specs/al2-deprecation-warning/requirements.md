# Requirements Document

## Introduction

The AWSLambdaPackager plugin defaults to Amazon Linux 2 as the base Docker image for building Lambda functions. An initial proposal (commit 7615923) switched the default to Amazon Linux 2023 for Swift >= 6.3, but community review identified that silently changing the build platform could cause deployment failures due to glibc and OpenSSL version differences between AL2 and AL2023. Binaries built for AL2023 may not run correctly when deployed to a `provided.al2` Lambda runtime.

Instead of changing the default, this feature keeps Amazon Linux 2 as the default build platform and introduces a prominent deprecation warning informing developers that Amazon Linux 2 reached End of Life in June 2025. The warning directs developers to explicitly opt in to Amazon Linux 2023 by re-issuing the build command with `--base-docker-image swift:6.3-amazonlinux2023`. Additionally, developers who switch to building on AL2023 must be informed that they also need to update their Lambda deployment to use the `provided.al2023` runtime instead of `provided.al2`. Amazon Linux 2023 will become the new default after June 30, 2025.

## Glossary

- **Packager_Plugin**: The `AWSLambdaPackager` Swift Package Manager command plugin that builds and archives Lambda functions for deployment.
- **Base_Docker_Image**: The Docker image used as the build environment for cross-compiling Swift code to Amazon Linux.
- **AL2**: Amazon Linux 2, the Linux distribution that reached End of Life in June 2025.
- **AL2023**: Amazon Linux 2023, the successor Linux distribution for AWS Lambda deployments.
- **Deprecation_Warning**: A prominent multi-line message printed to standard output alerting developers that AL2 is deprecated.
- **Native_Build**: A build performed directly on the host machine (without Docker) when the host is already running Amazon Linux.
- **Docker_Build**: A build performed inside a Docker container using the specified base image.

## Requirements

### Requirement 1: Default Base Docker Image

**User Story:** As a developer, I want the packager plugin to default to Amazon Linux 2 as the base Docker image, so that existing build workflows continue to work without changes until the migration deadline.

**Implementation Note:** Revert the base Docker image logic to the code before commit 7615923 (i.e., always use `amazonlinux2` regardless of Swift version).

#### Acceptance Criteria

1. WHEN no `--base-docker-image` option is provided and no `--swift-version` option is provided, THE Packager_Plugin SHALL use `swift:amazonlinux2` as the Base_Docker_Image.
2. WHEN no `--base-docker-image` option is provided and a `--swift-version` option is provided with a value matching the pattern `<major>`, `<major>.<minor>`, or `<major>.<minor>.<patch>` where each component is a non-negative integer, THE Packager_Plugin SHALL use `swift:<version>-amazonlinux2` as the Base_Docker_Image, where `<version>` is the exact string provided by the user.
3. WHEN a `--base-docker-image` option is provided and no `--swift-version` option is provided, THE Packager_Plugin SHALL use the user-specified image as the Base_Docker_Image.
4. IF both `--base-docker-image` and `--swift-version` options are provided, THEN THE Packager_Plugin SHALL reject the command with an error message indicating that `--swift-version` and `--base-docker-image` are mutually exclusive.

### Requirement 2: Deprecation Warning Display in Docker Build

**User Story:** As a developer building with Docker, I want to see a prominent deprecation warning when AL2 is used, so that I am informed about the upcoming migration requirement.

#### Acceptance Criteria

1. WHEN the Base_Docker_Image contains the string "amazonlinux2" and does not contain the string "amazonlinux2023", THE Packager_Plugin SHALL print the Deprecation_Warning before starting the Docker_Build.
2. THE Deprecation_Warning SHALL include a message stating that Amazon Linux 2 reached End of Life in June 2025.
3. THE Deprecation_Warning SHALL include a message stating that developers must migrate to Amazon Linux 2023.
4. THE Deprecation_Warning SHALL include a message stating that Amazon Linux 2023 will become the default after June 30, 2025.
5. THE Deprecation_Warning SHALL include the exact command option `--base-docker-image swift:6.3-amazonlinux2023` that developers can use to switch to AL2023 immediately.
6. THE Deprecation_Warning SHALL inform developers that when switching to AL2023, they must also update their Lambda deployment to use the `provided.al2023` runtime.
7. THE Deprecation_Warning SHALL include the URL `https://aws.amazon.com/amazon-linux-2` for reference.
8. THE Deprecation_Warning SHALL be visually prominent by using a separator line of at least 60 repeated characters above and below the warning text, with at least one empty line separating the warning block from surrounding build output.
8. WHEN the Deprecation_Warning has been printed, THE Packager_Plugin SHALL continue the Docker_Build to completion without halting or requiring user confirmation.
9. WHEN multiple products are built in a single invocation and the Base_Docker_Image triggers the deprecation condition, THE Packager_Plugin SHALL print the Deprecation_Warning exactly once before the first Docker_Build starts.

### Requirement 3: Deprecation Warning Display in Native Build on AL2

**User Story:** As a developer running the packager natively on Amazon Linux 2, I want to see the deprecation warning, so that I am informed about the upcoming migration requirement.

#### Acceptance Criteria

1. WHEN the Packager_Plugin reads `/etc/system-release` and the content starts with "Amazon Linux release 2" but does not start with "Amazon Linux release 2023", THE Packager_Plugin SHALL print the Deprecation_Warning to standard output.
2. WHEN the Packager_Plugin detects it is running natively on AL2, THE Packager_Plugin SHALL continue with the Native_Build after printing the Deprecation_Warning.
3. WHEN the Packager_Plugin detects it is running natively on AL2, THE Deprecation_Warning SHALL instruct the developer to switch to an Amazon Linux 2023 environment.
4. WHEN the Packager_Plugin detects it is running natively on AL2, THE Deprecation_Warning SHALL include the URL `https://aws.amazon.com/amazon-linux-2` for reference.
5. WHEN the Packager_Plugin detects it is running natively on AL2, THE Deprecation_Warning SHALL be visually prominent by using separator lines and whitespace to distinguish it from other build output.

### Requirement 4: Normal Build on AL2023

**User Story:** As a developer who has already migrated to Amazon Linux 2023, I want the build to proceed normally without any deprecation warning, so that my workflow is not interrupted.

#### Acceptance Criteria

1. WHEN the Base_Docker_Image contains the string "amazonlinux2023", THE Packager_Plugin SHALL execute the Docker_Build to completion and produce the expected archive artifacts without printing the Deprecation_Warning to standard output.
2. WHEN the Packager_Plugin reads the file `/etc/system-release` and its content contains the string "Amazon Linux 2023", THE Packager_Plugin SHALL execute the Native_Build to completion and produce the expected archive artifacts without printing the Deprecation_Warning to standard output.
3. IF the Base_Docker_Image contains the string "amazonlinux2023", THEN THE Packager_Plugin SHALL NOT print any message referencing Amazon Linux 2 End of Life or migration to standard output.

### Requirement 5: Help Message Update

**User Story:** As a developer, I want the help message to accurately reflect the current default base Docker image, so that I understand the plugin's behavior.

#### Acceptance Criteria

1. THE Packager_Plugin help message for the `--base-docker-image` option SHALL state that the default base Docker image is `swift:<version>-amazonlinux2`.
2. THE Packager_Plugin help message for the `--base-docker-image` option SHALL include a note stating that Amazon Linux 2023 will become the default after June 30, 2025.
3. WHEN the user passes `--help` to the archive command, THE Packager_Plugin SHALL display the help message containing both the current default image name and the Amazon Linux 2023 transition note.

### Requirement 6: Documentation Update

**User Story:** As a developer reading the project documentation, I want the documentation to reflect the current default behavior and migration path, so that I can plan my migration.

#### Acceptance Criteria

1. THE quick-setup documentation SHALL show `swift:amazonlinux2` as the Docker image in the example build output of the archive step.
2. THE quick-setup documentation SHALL include a note adjacent to the archive step stating that Amazon Linux 2 is the current default build environment and that a future version will migrate to Amazon Linux 2023.
3. THE readme documentation SHALL use `provided.al2` as the value of the `--runtime` flag in the `aws lambda create-function` deployment command.
4. THE readme documentation SHALL include a note adjacent to the archive command documenting the `--base-docker-image swift:6.3-amazonlinux2023` flag as an option for developers who want to migrate to Amazon Linux 2023 early.
