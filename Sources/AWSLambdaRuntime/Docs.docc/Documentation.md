# ``AWSLambdaRuntime``

An AWS Lambda runtime for the Swift programming language

## Overview

Many modern systems have client components like iOS, macOS or watchOS applications as well as server components that those clients interact with. Serverless functions are often the easiest and most efficient way for client application developers to extend their applications into the cloud.

Serverless functions are increasingly becoming a popular choice for running event-driven or otherwise ad-hoc compute tasks in the cloud. They power mission critical microservices and data intensive workloads. In many cases, serverless functions allow developers to more easily scale and control compute costs given their on-demand nature.

When using serverless functions, attention must be given to resource utilization as it directly impacts the costs of the system. This is where Swift shines! With its low memory footprint, deterministic performance, and quick start time, Swift is a fantastic match for the serverless functions architecture.

Combine this with Swift's developer friendliness, expressiveness, and emphasis on safety, and we have a solution that is great for developers at all skill levels, scalable, and cost effective.

Swift AWS Lambda Runtime was designed to make building Lambda functions in Swift simple and safe. The library is an implementation of the [AWS Lambda Runtime API](https://docs.aws.amazon.com/lambda/latest/dg/runtimes-api.html) and uses an embedded asynchronous HTTP client based on [SwiftNIO](https://github.com/apple/swift-nio) that is fine-tuned for performance in the AWS Lambda Runtime context. The library provides a multi-tier API that allows building a range of Lambda functions: from quick and simple closures to complex, performance-sensitive event handlers.

## Topics

### Essentials

- <doc:/tutorials/table-of-content>
- <doc:quick-setup>
- <doc:Deployment>

### Advanced Deployment

- <doc:managed-instances>
