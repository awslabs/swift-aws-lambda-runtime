# OCI container image

This example shows how to package and deploy a Swift Lambda function as an
**OCI container image** instead of a ZIP archive.

The function code itself is intentionally identical to [HelloWorld](../HelloWorld):
it takes a `String` and returns a `String`. What differs is the *packaging*. This
example uses `--archive-format oci` to build a container image, and `lambda-deploy`
pushes it to Amazon ECR and creates a container-image Lambda function.

## When to use a container image

A ZIP archive is the simplest option and gives the fastest cold starts for most
functions. Reach for a container image when:

- **Your deployment package is larger than the ZIP limits.** ZIP functions are capped
  at 50 MB (zipped) / 250 MB (unzipped); a container image can be up to 10 GB. Large
  dependencies, ML models, or bundled data fit comfortably in an image.
- **You need extra binaries, shared libraries, or system packages at runtime.** Tools
  your function shells out to (e.g. `ffmpeg`), native `.so` dependencies, or OS packages
  can be installed into the image with ordinary `dnf install` / `COPY` steps.
- **You already build and ship with containers.** An image in Amazon ECR slots into the
  same CI/CD, scanning, and registry tooling as the rest of your services.

If none of these apply, prefer the default ZIP packaging. See the other examples.

## Prerequisites

- Docker **or** Apple's [`container`](https://github.com/apple/container) CLI, installed
  and started. The same CLI is used to build the image and (at deploy time) to push it to Amazon ECR.
- For deployment: an AWS account with credentials configured (`aws configure`, environment
  variables, or an SSO session) and permission to use Amazon ECR and AWS Lambda.

> [!NOTE]
> The commands below use `--disable-sandbox`. Building and pushing an OCI image shells out
> to the container CLI, which talks to its local daemon over a socket the SwiftPM plugin
> sandbox does not allow. Apple's `container` in particular requires the sandbox to be
> disabled. This is why the OCI commands differ from the ZIP examples (which use
> `--allow-network-connections docker`).

## Build & package

Build the function and package it as an OCI image:

```bash
swift package --disable-sandbox lambda-build --archive-format oci
```

To build with Apple's `container` CLI instead of Docker, add `--cross-compile container`.

This compiles the executable for Amazon Linux 2023, then builds a minimal Amazon Linux
2023 image (`public.ecr.aws/amazonlinux/amazonlinux:2023-minimal`) with your binary as the
`bootstrap` entrypoint. The image is tagged locally as `swift-lambda/ociimage:latest`
(OCI image references must be lowercase, so the product name is lowercased).

> [!IMPORTANT]
> `lambda-build --archive-format oci` only builds the image **locally**. It does not push
> it. Pushing to Amazon ECR and creating/updating the function happens during
> `lambda-deploy`, which is the step that holds your AWS credentials. This mirrors the ZIP
> flow: `lambda-build` produces the artifact, `lambda-deploy` uploads it.

To build from a different base image, for example to add system packages, pass
`--base-oci-image <name>`. Use a glibc-compatible Amazon Linux 2023 base so it matches the
environment your binary was compiled in.

## Deploy

```bash
swift package --disable-sandbox lambda-deploy
```

For an image artifact, `lambda-deploy` will:

1. ensure an Amazon ECR repository exists (creating it if needed),
2. obtain an ECR authorization token and log the container CLI in,
3. tag and push the local image to ECR,
4. resolve the single-architecture child manifest by digest (Lambda does not accept
   multi-architecture image indexes), and
5. create or update the Lambda function with `PackageType=Image`.

`lambda-deploy` reads the `build-manifest.json` that `lambda-build` wrote next to the
image to learn that this is an image artifact, which container CLI built it, and which
architecture it targets. To override the CLI used for the push, pass
`--cross-compile <docker|container>`.

> [!NOTE]
> AWS does not allow changing the package type (ZIP ↔ image) of an existing function. If a
> function with the same name already exists with a different package type, `lambda-deploy`
> stops with an error; delete the function and redeploy.

## Invoke your Lambda function

```bash
aws lambda invoke \
  --function-name OCIImage \
  --payload $(echo \"Seb\" | base64) \
  out.txt && cat out.txt && rm out.txt
```

The payload is expected to be a valid JSON string, hence the surrounding quotes (`"`).
This should output:

```
{
    "StatusCode": 200,
    "ExecutedVersion": "$LATEST"
}
"Hello Seb!"
```

## Undeploy

When done testing, delete the Lambda function (and its IAM role):

```bash
swift package --allow-network-connections all:443 lambda-deploy --delete
```

The ECR repository and the pushed image are retained. If you no longer need them, delete
the repository (and all images in it) with the AWS CLI:

```bash
aws ecr delete-repository --repository-name ociimage --region us-east-1 --force
```

The repository name is the lowercased function name, and `--force` also removes the images
it contains. Adjust `--region` to match where you deployed.

## ⚠️ Security and Reliability Notice

These are example applications for demonstration purposes. When deploying such
infrastructure in production environments, we strongly encourage you to follow best
practices for improved security and resiliency. See the notice in the
[HelloWorld example](../HelloWorld/README.md#%EF%B8%8F-security-and-reliability-notice).
