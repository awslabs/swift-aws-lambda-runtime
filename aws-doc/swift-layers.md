# Working with layers for Swift Lambda functions

We don't recommend using layers to manage dependencies for Lambda functions written in Swift. This is because Lambda functions in Swift compile into a single executable, which you provide to Lambda when you deploy your function. This executable contains your compiled function code, along with all of its dependencies. Using layers not only complicates this process, but also leads to increased cold start times because your functions need to manually load extra assemblies into memory during the init phase.

To use external dependencies with your Swift handlers, include them directly in your deployment package. By doing so, you simplify the deployment process and also take advantage of built-in Swift compiler optimizations such as dead code elimination and whole-module optimization. For an example of how to import and use a dependency like the AWS SDK for Swift in your function, see [Define Lambda function handlers in Swift](swift-handler.md).

## When layers might still be useful

Although layers are not recommended for dependency management in Swift, there are limited scenarios where layers can still be useful:

- **Shared configuration files**: If multiple functions need access to the same configuration files (such as `.json` or `.yaml` files), you can package them in a layer.
- **Machine learning models**: If your function loads large model files at runtime, packaging them in a layer can simplify updates to the model without redeploying the function code.
- **Shared native libraries**: If your function depends on native C libraries that aren't included in the Amazon Linux base image and are difficult to statically link, you can package them in a layer.

In these cases, the layer content is extracted to `/opt` in the function execution environment. You can access these files from your Swift code using standard file I/O:

```swift
import Foundation

let configPath = "/opt/config/settings.json"
let data = try Data(contentsOf: URL(fileURLWithPath: configPath))
```

For more general information about layers, see [Managing Lambda dependencies with layers](https://docs.aws.amazon.com/lambda/latest/dg/chapter-layers.html).
