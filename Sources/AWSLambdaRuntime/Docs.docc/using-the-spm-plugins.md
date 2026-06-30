# Using the SwiftPM Plugins

@Metadata {
    @PageKind(article)
    @PageColor(orange)
    @SupportedLanguage(swift)
    @PageImage(source: "lambda.png", alt: "AWS Lambda", purpose: icon)
}

Scaffold, build, and deploy your Lambda function with the bundled SwiftPM command plugins.

## Overview

> Warning: The command plugins require **Swift 6.4 or later**. On older toolchains, `swift package lambda-init`, `lambda-build`, and `lambda-deploy` are not available, use the `archive` plugin instead. After installing [swiftly](https://www.swift.org/install/macos/), run `swiftly install 6.4.x-snapshot`.

Swift AWS Lambda Runtime ships three SwiftPM command plugins that cover the full
lifecycle of a Lambda function, from creating the project to deploying it on AWS:

- **`lambda-init`** — scaffold a new Lambda function from a template.
- **`lambda-build`** — compile and package your function for Amazon Linux 2023.
- **`lambda-deploy`** — deploy, update, or delete your function on AWS, including
  its IAM role and an optional Function URL.

The plugins become available as soon as your package depends on
`swift-aws-lambda-runtime`. You invoke them with `swift package <plugin-name>`.
Each plugin accepts `--help` to print its full list of options, and `--verbose`
to produce detailed output for debugging.

Because SwiftPM plugins run in a sandbox, some plugins require you to explicitly
grant permissions on the command line:

- `lambda-init` needs `--allow-writing-to-package-directory` to write files.
- `lambda-build` needs `--allow-network-connections docker` to
  reach the build container.
- `lambda-deploy` needs `--allow-network-connections all:443` to call the AWS APIs.

> Tip: You can see a quick end-to-end walkthrough in <doc:quick-setup>.

## lambda-init

`lambda-init` scaffolds a HelloWorld Lambda function into your package. By
default it creates a function that receives a JSON document and responds with
another JSON document. It detects your package's entry point file, backs it up
with a `.bak` extension, and replaces it with the generated template.

```sh
swift package lambda-init --allow-writing-to-package-directory
```

Pass `--with-url` to instead scaffold a function that is exposed through a
Function URL.

```sh
swift package lambda-init --allow-writing-to-package-directory --with-url
```

### Options

| Option | Description |
| --- | --- |
| `--with-url` | Create a Lambda function exposed with a URL. |
| `--allow-writing-to-package-directory` | Don't ask for permission to write files. |
| `--verbose` | Produce verbose output for debugging. |
| `--help` | Show help information. |

## lambda-build

`lambda-build` compiles your executable targets for Amazon Linux 2023 and
packages them into deployment ZIP archives. The build runs inside a container,
so you must have [Docker](https://docs.docker.com/desktop/install/mac-install/)
(or `container`) installed and started.

```sh
swift package --allow-network-connections docker lambda-build
```

By default the plugin builds in `release` configuration, uses the latest Swift
`amazonlinux2023` base image, and strips debug symbols from the binary. The
resulting archive is written under
`.build/plugins/AWSLambdaBuilder/outputs/...`.

> Note: Amazon Linux 2 is deprecated since June 30, 2026. The plugin defaults
> to Amazon Linux 2023.

To build for a specific Swift version, or to keep debug symbols:

```sh
swift package --allow-network-connections docker lambda-build \
  --swift-version 6.3 \
  --no-strip
```

### Options

| Option | Description |
| --- | --- |
| `--output-path <path>` | The path of the binary package. (default: `.build/plugins/AWSLambdaBuilder/outputs/...`) |
| `--products <list>` | The list of executable targets to build. (default: taken from `Package.swift`) |
| `--configuration <name>` | The build configuration, `debug` or `release`. (default: `release`) |
| `--swift-version <version>` | The Swift version to use for building. (default: latest) Cannot be combined with `--base-docker-image`. |
| `--base-docker-image <name>` | The base Docker image to build with. (default: `swift:<version>-amazonlinux2023`) Cannot be combined with `--swift-version`. |
| `--disable-docker-image-update` | Do not attempt to update the Docker image. |
| `--cross-compile <method>` | The cross-compilation method: `docker`, `container`, `swift-static-sdk`, or `custom-sdk`. (default: `docker`) `swift-static-sdk` and `custom-sdk` are not yet supported. |
| `--archive-format <format>` | The packaging format: `zip` or `oci`. (default: `zip`) See [Building an OCI image](#Building-an-OCI-image). |
| `--base-oci-image <name>` | The base image for the OCI image when `--archive-format oci` is used. (default: `public.ecr.aws/amazonlinux/amazonlinux:2023-minimal`) |
| `--no-strip` | Do not strip debug symbols from the binary. |
| `--verbose` | Produce verbose output for debugging. |
| `--help` | Show help information. |

### Building an OCI image

By default `lambda-build` produces a ZIP archive, which is the simplest option
and gives the fastest cold starts for most functions. Packaging your function as
a container image instead is useful when:

- **Your deployment package is larger than the ZIP limits.** A ZIP-packaged
  function is capped at 50 MB zipped / 250 MB unzipped, whereas a container image
  can be up to 10 GB. Large dependencies, ML models, or bundled data that blow
  past the ZIP limit fit comfortably in an image.
- **You need extra binaries, shared libraries, or system packages at runtime.**
  Tools your function shells out to (e.g. `ffmpeg`), native `.so` dependencies, or
  any OS packages can be installed into the image with ordinary `dnf install` /
  `COPY` steps, instead of being awkwardly vendored into a ZIP.
- **You already build and ship with containers.** If your team's CI/CD, scanning,
  and artifact registries are container-based, an image in Amazon ECR slots into
  the same tooling and promotion workflow as the rest of your services.
- **You want a reproducible, self-contained runtime.** The image pins the OS, the
  Swift runtime libraries, and your binary together, so what you test locally is
  byte-for-byte what runs in Lambda.

If none of these apply, prefer the default ZIP format.

Pass `--archive-format oci` to build an
[OCI image](https://docs.aws.amazon.com/lambda/latest/dg/images-create.html)
suitable for deployment as a container-image Lambda function:

```sh
swift package --allow-network-connections docker lambda-build \
  --archive-format oci
```

This builds a minimal Amazon Linux 2023 image (`public.ecr.aws/amazonlinux/amazonlinux:2023-minimal`)
with your compiled binary as the `bootstrap` entrypoint, using the same container
CLI selected by `--cross-compile` (`docker` or `container`). The image is built
for a single architecture and tagged locally as `swift-lambda/<product>:latest`.

To build from a different base image, for example to add system packages or to
use `public.ecr.aws/lambda/provided:al2023`, pass `--base-oci-image`:

```sh
swift package --allow-network-connections docker lambda-build \
  --archive-format oci \
  --base-oci-image public.ecr.aws/lambda/provided:al2023
```

Use a glibc-compatible Amazon Linux 2023 base so the image matches the
`swift:*-amazonlinux2023` environment your binary was compiled in.

> Important: `lambda-build --archive-format oci` only builds the image **locally**;
> it does **not** push it to a registry. Pushing the image to Amazon ECR and
> creating or updating the container-image function happens during `lambda-deploy`,
> which is the step that holds your AWS credentials and network access. This mirrors
> the ZIP flow, where `lambda-build` produces the artifact and `lambda-deploy`
> uploads it.

Alongside the artifact, `lambda-build` writes a `build-manifest.json` recording
the package type, architecture, and (for images) the container CLI and local tag.
`lambda-deploy` reads this manifest to determine how to deploy.

## lambda-deploy

`lambda-deploy` deploys the ZIP archive produced by `lambda-build` to AWS. It
manages the full IAM role lifecycle, automatically creating a role with the
`AWSLambdaBasicExecutionRole` policy when you don't provide an existing one. It
also stages large archives (over 50 MB) through S3.

> Tip: For a step-by-step walkthrough, including how credentials are resolved,
> see <doc:deploying-with-the-plugin>.

> Be sure [to have an AWS Account](https://docs.aws.amazon.com/accounts/latest/reference/manage-acct-creating.html)
> and the [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
> installed and configured (`aws configure`) before deploying.

```sh
swift package --allow-network-connections all:443 lambda-deploy
```

On success, the plugin reports the function ARN and a ready-to-use
`aws lambda invoke` command.

To expose the function through a Function URL, use `--with-url`. The URL is
protected with `AWS_IAM` authentication, restricted to authenticated principals
in your AWS account:

```sh
swift package --allow-network-connections all:443 lambda-deploy --with-url
```

When you're done, delete the function, its IAM role, and the Function URL (if
any) with `--delete`:

```sh
swift package --allow-network-connections all:443 lambda-deploy --delete
```

### Options

| Option | Description |
| --- | --- |
| `--with-url` | Create a Function URL using `AWS_IAM` authentication. |
| `--delete` | Delete the Lambda function, its IAM role, and Function URL (if any). |
| `--region <region>` | The AWS region to deploy to. (default: resolved from AWS configuration) |
| `--profile <profile-name>` | The named AWS profile to use for credentials and region. (default: default credential provider chain) |
| `--iam-role <role-arn>` | The ARN of an existing IAM role for the function. (default: create a new role) |
| `--input-directory <path>` | The directory containing the ZIP archive produced by `lambda-build`. (default: `.build/plugins/AWSLambdaBuilder/outputs/...`) |
| `--architecture <arch>` | The function architecture, `x64` or `arm64`. (default: host architecture) |
| `--products <list>` | The list of executable targets to deploy. (default: taken from `Package.swift`) |
| `--verbose` | Produce verbose output for debugging. |
| `--help` | Show help information. |

## A typical workflow

Putting the three plugins together, a typical workflow looks like this:

```sh
# 1. Scaffold a new function
swift package lambda-init --allow-writing-to-package-directory

# 2. Build and package it for Amazon Linux 2023
swift package --allow-network-connections docker lambda-build

# 3. Deploy it to AWS
swift package --allow-network-connections all:443 lambda-deploy
```

> Note: The legacy `archive` command remains available as a deprecated alias for
> `lambda-build`.
