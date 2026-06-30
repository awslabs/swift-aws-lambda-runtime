# Deployment prerequisites

@Metadata {
    @PageKind(article)
    @PageColor(orange)
    @SupportedLanguage(swift)
    @PageImage(source: "lambda.png", alt: "AWS Lambda", purpose: icon)
}

What you need before deploying: an AWS account, credentials, the AWS CLI, a region, and an execution role.

## Overview

Whichever deployment method you choose, you need an AWS account, credentials, and a packaged Swift Lambda function. This article also explains two concepts that apply to every deployment: choosing the AWS Region, and the Lambda execution IAM role.

## Prerequisites

1. Your AWS Account

   To deploy a Lambda function on AWS, you need an AWS account. If you don't have one yet, you can create a new account at [aws.amazon.com](https://signin.aws.amazon.com/signup?request_type=register). It takes a few minutes to register. A credit card is required.

   We do not recommend using the root credentials you entered at account creation time for day-to-day work. Instead, create an [Identity and Access Manager (IAM) user](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_users.html) with the necessary permissions and use its credentials.

   Follow the steps in [Create an IAM User in your AWS account](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_users_create.html).

   We suggest to attach the `AdministratorAccess` policy to the user for the initial setup. For production workloads, you should follow the principle of least privilege and grant only the permissions required for your users. The ['AdministratorAccess' gives the user permission](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_managed-vs-inline.html#aws-managed-policies) to manage all resources on the AWS account.

2. AWS Security Credentials

   [AWS Security Credentials](https://docs.aws.amazon.com/IAM/latest/UserGuide/security-creds.html) are required to access the AWS console, AWS APIs, or to let tools access your AWS account.

   AWS Security Credentials can be **temporary credentials** (obtained through AWS IAM Identity Center single sign-on, by assuming an IAM role, or from an instance or container role) or **long-term credentials** (an Access Key ID and a Secret Access Key attached to an IAM user).

   We strongly recommend using **temporary credentials**. They are short-lived, scoped, and rotated automatically, so a leaked credential stops working quickly. AWS recommends against creating long-term access keys for IAM users. For human access, use [AWS IAM Identity Center](https://docs.aws.amazon.com/singlesignon/latest/userguide/what-is.html) (SSO) and sign in with `aws sso login`. When you use SSO with your enterprise identity tools (such as Microsoft Entra ID, Okta, and others) or assume an IAM role, you receive temporary credentials that the AWS CLI and the deploy plugin pick up automatically.

   A typical set of temporary credentials includes a session token in addition to the access key (redacted for security).

   ```json
   {
     "Credentials": {
        "AccessKeyId": "ASIA...FFSD",
        "SecretAccessKey": "Xn...NL",
        "SessionToken": "IQ...pV",
        "Expiration": "2024-11-23T11:32:30+00:00"
     }
   }
   ```

   > Long-term IAM user access keys remain a possibility and are read from `~/.aws/credentials` like any other source, but we strongly advise against them. They do not expire on their own, so a leaked key stays valid until you manually rotate or delete it. If you must use them, follow the [best practices for managing access keys](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_access-keys.html#Securing_access-keys) and rotate them regularly.

3. AWS CLI and credentials configuration.

   To deploy with the `lambda-deploy` plugin from your local machine, install the [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) and configure access to your account. The plugin reads whatever credentials your AWS CLI configuration resolves, so any standard setup works.

   For short-term credentials through IAM Identity Center (recommended), configure an SSO profile and sign in:

   ```sh
   aws configure sso
   aws sso login
   ```

   The plain `aws configure` command is also available. Prefer it only when you cannot use SSO, and avoid storing long-term access keys in `~/.aws/credentials` whenever possible:

   ```sh
   aws configure
   ```

   > On EC2, ECS, or EKS, credentials are typically provided automatically by the instance or task role, so no local configuration is required in those environments.

4. A Swift Lambda function to deploy.

   You need a Swift Lambda function to deploy. If you don't have one yet, you can scaffold one using the `lambda-init` plugin:

   ```sh
   swift package lambda-init --allow-writing-to-package-directory
   ```

   Or use one of the examples in the [Examples](https://github.com/awslabs/swift-aws-lambda-runtime/tree/main/Examples) directory.

   Compile and package the function using the following command:

   ```sh
   swift package --allow-network-connections docker lambda-build
   ```

   This command creates a ZIP file with the compiled Swift code. The ZIP file is located in the `.build/plugins/AWSLambdaBuilder/outputs/AWSLambdaBuilder/MyLambda/MyLambda.zip` folder.

   The name of the ZIP file depends on the target name you entered in the `Package.swift` file.

## Choosing the AWS Region where to deploy

[AWS Global infrastructure](https://aws.amazon.com/about-aws/global-infrastructure/) spans over 34 geographic Regions (and continuously expanding). When you create a resource on AWS, such as a Lambda function, you have to select a geographic region where the resource will be created. The two main factors to consider to select a Region are the physical proximity with your users and geographical compliance.

Physical proximity helps you reduce the network latency between the Lambda function and your customers. For example, when the majority of your users are located in South-East Asia, you might consider deploying in the Singapore, the Malaysia, or Jakarta Region.

Geographical compliance, also known as data residency compliance, involves following location-specific regulations about how and where data can be stored and processed.

## The Lambda execution IAM role

A Lambda execution role is an AWS Identity and Access Management (IAM) role that grants your Lambda function the necessary permissions to interact with other AWS services and resources. Think of it as a security passport that determines what your function is allowed to do within AWS. For example, if your Lambda function needs to read files from Amazon S3, write logs to Amazon CloudWatch, or access an Amazon DynamoDB table, the execution role must include the appropriate permissions for these actions.

When you create a Lambda function, you must specify an execution role. This role contains two main components: a trust policy that allows the Lambda service itself to assume the role, and permission policies that determine what AWS resources the function can access. By default, Lambda functions get basic permissions to write logs to CloudWatch Logs, but any additional permissions (like accessing S3 buckets or sending messages to SQS queues) must be explicitly added to the role's policies. Following the principle of least privilege, it's recommended to grant only the minimum permissions necessary for your function to operate, helping maintain the security of your serverless applications.
