# Project Structure

## Root Directory

- `Package.swift` - Swift Package Manager manifest with dependencies and targets
- `Package@swift-6.0.swift` - Swift 6.0 specific package manifest
- `Makefile` - Build automation and convenience commands
- `readme.md` - Main project documentation and getting started guide

## Core Source Code

### `Sources/AWSLambdaRuntime/`
Main runtime library implementation:

- `Lambda.swift` - Core Lambda runtime loop and execution logic
- `LambdaRuntime.swift` - Main runtime class and public API
- `LambdaHandlers.swift` - Handler protocol definitions and implementations
- `LambdaContext.swift` - Request context and metadata
- `LambdaRuntimeClient.swift` - HTTP client for AWS Lambda Runtime API
- `Lambda+Codable.swift` - JSON encoding/decoding support
- `Lambda+LocalServer.swift` - Local testing server implementation
- `LambdaRuntimeError.swift` - Error types and handling
- `ControlPlaneRequest.swift` - AWS control plane communication
- `Utils.swift` - Utility functions and helpers

### `Sources/AWSLambdaRuntime/FoundationSupport/`
Foundation integration and JSON support

### `Sources/AWSLambdaRuntime/Docs.docc/`
Documentation and tutorials using DocC

### `Sources/MockServer/`
Mock server for performance testing

## Examples Directory

### `Examples/`
Comprehensive example implementations:

- `_MyFirstFunction/` - Quick start tutorial with deployment script
- `HelloWorld/` - Basic Lambda function example
- `HelloJSON/` - JSON input/output handling
- `APIGateway/` - REST API with API Gateway integration
- `APIGateway+LambdaAuthorizer/` - API with Lambda authorizer
- `Streaming/` - Response streaming example
- `StreamingFromEvent/` - Event-driven streaming
- `BackgroundTasks/` - Background processing after response
- `S3EventNotifier/` - S3 event handling
- `S3_AWSSDK/` - AWS SDK integration
- `S3_Soto/` - Soto library integration
- `CDK/` - AWS CDK deployment example
- `Testing/` - Unit testing patterns
- `Tutorial/` - Step-by-step learning materials

## Testing

### `Tests/AWSLambdaRuntimeTests/`
Comprehensive test suite covering:
- Runtime functionality
- Handler implementations
- Error scenarios
- Integration tests

## Build and Deployment

### `Plugins/`
Swift Package Manager plugins:
- `AWSLambdaPackager` - Creates deployment-ready ZIP archives

### `.build/`
Build artifacts and intermediate files (generated)

## Configuration Files

- `.swift-version` - Swift toolchain version specification
- `.swift-format` - Code formatting configuration
- `.gitignore` - Git ignore patterns
- `.licenseignore` - License checking exclusions

## Development Tools

### `.devcontainer/`
VS Code development container configuration

### `.vscode/`
VS Code workspace settings and configurations

### `scripts/`
Build and deployment automation scripts

## Documentation

- `CODE_OF_CONDUCT.md` - Community guidelines
- `CONTRIBUTING.md` - Contribution guidelines
- `CONTRIBUTORS.txt` - Project contributors
- `SECURITY.md` - Security policy and reporting
- `LICENSE.txt` - Apache 2.0 license
- `NOTICE.txt` - Third-party notices

## Naming Conventions

- **Files**: PascalCase for Swift files (e.g., `LambdaRuntime.swift`)
- **Directories**: PascalCase for major components, lowercase for utilities
- **Examples**: Descriptive names indicating functionality
- **Tests**: Mirror source structure with `Tests` suffix