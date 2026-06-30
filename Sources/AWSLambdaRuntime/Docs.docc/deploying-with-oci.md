# Deploy as an OCI container image

@Metadata {
    @PageKind(article)
    @PageColor(orange)
    @SupportedLanguage(swift)
    @PageImage(source: "lambda.png", alt: "AWS Lambda", purpose: icon)
}

Package your Swift Lambda function as an OCI container image and deploy it to AWS through Amazon ECR.

## Overview

> Warning: The command plugins require **Swift 6.4 or later**. On older toolchains, `swift package lambda-build` and `lambda-deploy` are not available. After installing [swiftly](https://www.swift.org/install/macos/), run `swiftly install 6.4.x-snapshot`.

By default `lambda-build` produces a ZIP archive. That is the simplest option and gives the fastest cold starts for most functions. Lambda also accepts a function packaged as an [OCI container image](https://docs.aws.amazon.com/lambda/latest/dg/images-create.html). Pass `--archive-format oci` and `lambda-build` builds the image locally, then `lambda-deploy` pushes it to Amazon ECR and creates a container-image function. The function code is the same either way. Only the packaging changes.

> See <doc:deploying-prerequisites> for the AWS account, credentials, and region every deployment needs. This article assumes you can already deploy a ZIP function with <doc:deploying-with-the-plugin>.

### When to use a container image

A container image is the right choice when:

- Your package is larger than the ZIP limits. ZIP functions are capped at 50 MB zipped and 250 MB unzipped. An image can be up to 10 GB, which fits large dependencies, ML models, or bundled data.
- You need extra binaries, shared libraries, or system packages at runtime. Install them into the image with regular `dnf install` or `COPY` steps.
- You already build and ship with containers, so an image in Amazon ECR fits your existing CI/CD and registry tooling.

Otherwise, prefer the default ZIP packaging in <doc:deploying-with-the-plugin>.

## Prerequisites

- Docker or Apple's [`container`](https://github.com/apple/container) CLI, installed and started. The same CLI builds the image and, at deploy time, pushes it to Amazon ECR.
- The [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) installed and configured with `aws configure`, with permission to use Amazon ECR and AWS Lambda.

> Note: The commands below use `--disable-sandbox`. Building and pushing an image runs the container CLI, which talks to its local daemon over a socket the SwiftPM plugin sandbox does not allow. Apple's `container` in particular needs the sandbox disabled. This is why the OCI commands differ from the ZIP workflow.

## Build the image

```sh
swift package --disable-sandbox lambda-build --archive-format oci
```

To use Apple's `container` CLI instead of Docker, add `--cross-compile container`.

This compiles the executable for Amazon Linux 2023, then builds a minimal Amazon Linux 2023 image (`public.ecr.aws/amazonlinux/amazonlinux:2023-minimal`) with your binary as the `bootstrap` entrypoint. The image targets a single architecture and is tagged locally as `swift-lambda/<product>:latest`, lowercased, since OCI image references must be lowercase.

`lambda-build --archive-format oci` builds the image locally. It does not push it. The push to Amazon ECR and the function create or update happen during `lambda-deploy`, the step that holds your AWS credentials. This matches the ZIP flow, where `lambda-build` produces the artifact and `lambda-deploy` uploads it.

To build from a different base image, for example to add system packages, pass `--base-oci-image <name>`. Use a glibc-compatible Amazon Linux 2023 base so it matches the environment your binary was compiled in.

Next to the image, `lambda-build` writes a `build-manifest.json` recording the package type, architecture, container CLI, and local image tag. `lambda-deploy` reads it to decide how to deploy.

## Deploy the image

```sh
swift package --disable-sandbox lambda-deploy
```

For an image artifact, `lambda-deploy`:

1. ensures an Amazon ECR repository exists, creating it if needed,
2. obtains an ECR authorization token and logs the container CLI in,
3. tags and pushes the local image to ECR,
4. resolves the single-architecture child manifest by digest. Both Docker and `container` push a multi-architecture image index, which Lambda does not accept, so the deployer selects the child manifest that matches the target architecture, then
5. creates or updates the Lambda function with `PackageType=Image`.

The deployer reads the architecture and container CLI from `build-manifest.json`. To override the CLI used for the push, pass `--cross-compile <docker|container>`.

> Note: AWS does not allow changing the package type of an existing function, ZIP to image or back. If a function with the same name already exists with a different package type, `lambda-deploy` stops with an error. Delete the function and redeploy.

When the deployment succeeds, the plugin reports the function ARN, region, and an invocation command.

## Invoke the function

```sh
aws lambda invoke \
  --function-name MyLambda \
  --payload $(echo '{"name":"World","age":30}' | base64) \
  /dev/stdout
```

## Delete the function

Remove the Lambda function and its IAM role:

```sh
swift package --allow-network-connections all:443 lambda-deploy --delete
```

The `--delete` path only calls AWS APIs, with no container CLI, so it runs under the standard network sandbox. The ECR repository and pushed image are kept. Delete the repository and its images with the AWS CLI when you no longer need them:

```sh
aws ecr delete-repository --repository-name mylambda --region us-east-1 --force
```

The repository name is the lowercased function name. Adjust `--region` to match where you deployed.

## See also

A complete, runnable example is in the [OCIImage example](https://github.com/awslabs/swift-aws-lambda-runtime/tree/main/Examples/OCIImage).
