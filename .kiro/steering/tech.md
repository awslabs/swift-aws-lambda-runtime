# Technology Stack

## Core Technologies

- **Swift 6.x**: Primary programming language (minimum Swift 6.0)
- **SwiftNIO**: Asynchronous networking framework for HTTP client implementation
- **Swift Package Manager**: Dependency management and build system
- **Docker**: Required for cross-compilation to Amazon Linux 2

## Key Dependencies

- `swift-nio`: Asynchronous event-driven network application framework
- `swift-log`: Logging API for Swift
- `swift-collections`: Additional collection types (DequeModule)
- `swift-service-lifecycle`: Service lifecycle management (optional trait)

## Platform Requirements

- **macOS**: Version 15 (Sequoia) or later for development
- **Target Runtime**: Amazon Linux 2 (provided.al2 runtime)
- **Architecture**: Supports both x86_64 and ARM64 (Apple Silicon)

## Build System

### Swift Package Manager Commands

```bash
# Build the project
swift build

# Run tests
swift test

# Format code
swift format format --parallel --recursive --in-place ./Package.swift Examples/ Sources/ Tests/

# Generate documentation
swift package generate-documentation --target AWSLambdaRuntime

# Preview documentation
swift package --disable-sandbox preview-documentation --target AWSLambdaRuntime
```

### Lambda-Specific Commands

```bash
# Initialize a new Lambda function
swift package lambda-init --allow-writing-to-package-directory

# Build and archive for AWS deployment
swift package archive --allow-network-connections docker

# Add Lambda runtime dependency
swift package add-dependency https://github.com/swift-server/swift-aws-lambda-runtime.git --branch main
swift package add-target-dependency AWSLambdaRuntime MyLambda --package swift-aws-lambda-runtime
```

### Local Testing

```bash
# Run locally (starts HTTP server on port 7000)
swift run

# Test with custom endpoint
LOCAL_LAMBDA_SERVER_INVOCATION_ENDPOINT=/2015-03-31/functions/function/invocations swift run

# Invoke local function
curl -v --header "Content-Type: application/json" --data @events/test.json http://127.0.0.1:7000/invoke
```

### Cross-Platform Build

```bash
# Build on Linux using Docker
docker run --rm -v $(pwd):/work swift:6.1 /bin/bash -c "cd /work && swift build && swift test"

# Using container command (alternative)
CONTAINER=podman make build-linux
```

## Deployment Tools

- **AWS CLI**: Command-line deployment
- **AWS SAM**: Serverless Application Model for infrastructure as code
- **AWS CDK**: Cloud Development Kit for programmatic infrastructure
- **Terraform**: Third-party infrastructure as code
- **Serverless Framework**: Third-party deployment framework