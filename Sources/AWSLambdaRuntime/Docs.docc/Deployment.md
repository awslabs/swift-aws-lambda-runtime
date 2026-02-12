# Deploying your Swift Lambda functions

@Metadata {
    @PageKind(article)
    @PageColor(orange)
    @SupportedLanguage(swift)
    @PageImage(source: "lambda.png", alt: "AWS Lambda", purpose: icon)
}

Learn how to deploy your Swift Lambda functions to AWS.

### Overview

There are multiple ways to deploy your Swift code to AWS Lambda. The very first time, you'll probably use the AWS Console to create a new Lambda function and upload your code as a zip file. However, as you iterate on your code, you'll want to automate the deployment process.

To take full advantage of the cloud, we recommend using Infrastructure as Code (IaC) tools like the [AWS Serverless Application Model (SAM)](https://aws.amazon.com/serverless/sam/) or [AWS Cloud Development Kit (CDK)](https://aws.amazon.com/cdk/). These tools allow you to define your infrastructure and deployment process as code, which can be version-controlled and automated.

In this section, we show you how to deploy your Swift Lambda functions using different AWS Tools. Alternatively, you might also consider using popular third-party tools like [Serverless Framework](https://www.serverless.com/), [Terraform](https://www.terraform.io/), or [Pulumi](https://www.pulumi.com/) to deploy Lambda functions and create and manage AWS infrastructure.

Here is the content of this guide:

  * [Prerequisites](#prerequisites)
  * [Choosing the AWS Region where to deploy](#choosing-the-aws-region-where-to-deploy)
  * [The Lambda execution IAM role](#the-lambda-execution-iam-role)
  * [Deploy your Lambda function with the AWS Console](#deploy-your-lambda-function-with-the-aws-console)
  * [Deploy your Lambda function with the AWS Command Line Interface (CLI)](#deploy-your-lambda-function-with-the-aws-command-line-interface-cli)
  * [Deploy your Lambda function with AWS Serverless Application Model (SAM)](#deploy-your-lambda-function-with-aws-serverless-application-model-sam)
  * [Deploy your Lambda function with AWS Cloud Development Kit (CDK)](#deploy-your-lambda-function-with-aws-cloud-development-kit-cdk)
  * [Third-party tools](#third-party-tools)

### Prerequisites

1. Your AWS Account

   To deploy a Lambda function on AWS, you need an AWS account. If you don't have one yet, you can create a new account at [aws.amazon.com](https://signin.aws.amazon.com/signup?request_type=register). It takes a few minutes to register. A credit card is required.

   We do not recommend using the root credentials you entered at account creation time for day-to-day work. Instead, create an [Identity and Access Manager (IAM) user](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_users.html) with the necessary permissions and use its credentials.
   
   Follow the steps in [Create an IAM User in your AWS account](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_users_create.html).
   
   We suggest to attach the `AdministratorAccess` policy to the user for the initial setup. For production workloads, you should follow the principle of least privilege and grant only the permissions required for your users. The ['AdministratorAccess' gives the user permission](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_managed-vs-inline.html#aws-managed-policies) to manage all resources on the AWS account.

2. AWS Security Credentials

   [AWS Security Credentials](https://docs.aws.amazon.com/IAM/latest/UserGuide/security-creds.html) are required to access the AWS console, AWS APIs, or to let tools access your AWS account.
  
   AWS Security Credentials can be **long-term credentials** (for example, an Access Key ID and a Secret Access Key attached to your IAM user) or **temporary credentials** obtained via other AWS API, such as when accessing AWS through single sign-on (SSO) or when assuming an IAM role.

   To follow the steps in this guide, you need to know your AWS Access Key ID and Secret Access Key. If you don't have them, you can create them in the AWS Management Console. Follow the steps in [Creating access keys for an IAM user](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_access-keys.html#Using_CreateAccessKey).

   When you use SSO with your enterprise identity tools (such as Microsoft entra ID –formerly Active Directory–, Okta, and others) or when you write scripts or code assuming an IAM role, you receive temporary credentials. These credentials are valid for a limited time, have a limited scope, and are rotated automatically. You can use them in the same way as long-term credentials. In addition to an AWS Access Key and Secret Access Key, temporary credentials include a session token.

   Here is a typical set of temporary credentials (redacted for security).

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

3. A Swift Lambda function to deploy.

   You need a Swift Lambda function to deploy. If you don't have one yet, you can use one of the examples in the [Examples](https://github.com/awslabs/swift-aws-lambda-runtime/tree/main/Examples) directory.

   Compile and package the function using the following command

   ```sh
   swift package archive --allow-network-connections docker
   ```

   This command creates a ZIP file with the compiled Swift code. The ZIP file is located in the `.build/plugins/AWSLambdaPackager/outputs/AWSLambdaPackager/MyLambda/MyLambda.zip` folder.

   The name of the ZIP file depends on the target name you entered in the `Package.swift` file.

   >[!NOTE]
   > When building on Linux, your current user must have permission to use docker. On most Linux distributions, you can do so by adding your user to the `docker` group with the following command: `sudo usermod -aG docker $USER`. You must log out and log back in for the changes to take effect.

   >[!NOTE]
   > If you encounter Docker credential store errors during the build, remove the `credsStore` entry from your `~/.docker/config.json` file or disable the plugin sandbox with `--disable-sandbox`. See [issue #609](https://github.com/awslabs/swift-aws-lambda-runtime/issues/609) for details.

   

### Choosing the AWS Region where to deploy

[AWS Global infrastructure](https://aws.amazon.com/about-aws/global-infrastructure/) spans over 34 geographic Regions (and continuously expanding). When you create a resource on AWS, such as a Lambda function, you have to select a geographic region where the resource will be created. The two main factors to consider to select a Region are the physical proximity with your users and geographical compliance. 

Physical proximity helps you reduce the network latency between the Lambda function and your customers. For example, when the majority of your users are located in South-East Asia, you might consider deploying in the Singapore, the Malaysia, or Jakarta Region.

Geographical compliance, also known as data residency compliance, involves following location-specific regulations about how and where data can be stored and processed.

### The Lambda execution IAM role

A Lambda execution role is an AWS Identity and Access Management (IAM) role that grants your Lambda function the necessary permissions to interact with other AWS services and resources. Think of it as a security passport that determines what your function is allowed to do within AWS. For example, if your Lambda function needs to read files from Amazon S3, write logs to Amazon CloudWatch, or access an Amazon DynamoDB table, the execution role must include the appropriate permissions for these actions.

When you create a Lambda function, you must specify an execution role. This role contains two main components: a trust policy that allows the Lambda service itself to assume the role, and permission policies that determine what AWS resources the function can access. By default, Lambda functions get basic permissions to write logs to CloudWatch Logs, but any additional permissions (like accessing S3 buckets or sending messages to SQS queues) must be explicitly added to the role's policies. Following the principle of least privilege, it's recommended to grant only the minimum permissions necessary for your function to operate, helping maintain the security of your serverless applications.

### Deploy your Lambda function with the AWS Console

In this section, we deploy the HelloWorld example function using the AWS Console. The HelloWorld function is a simple function that takes a `String` as input and returns a `String`.

Authenticate on the AWS console using your IAM username and password. On the top right side, select the AWS Region where you want to deploy, then navigate to the Lambda section.

![Console - Select AWS Region](console-10-regions)

#### Create the function 

Select **Create a function** to create a function.

![Console - Lambda dashboard when there is no function](console-20-dashboard)

Select **Author function from scratch**. Enter a **Function name** (`HelloWorld`) and select `Amazon Linux 2` as **Runtime**.
Select the architecture. When you compile your Swift code on a x84_64 machine, such as an Intel Mac, select `x86_64`. When you compile your Swift code on an Arm machine, such as the Apple Silicon M1 or more recent, select `arm64`.

Select **Create function**

![Console - create function](console-30-create-function)

On the right side, select **Upload from** and select **.zip file**.

![Console - select zip file](console-40-select-zip-file)

Select the zip file created with the `swift package archive --allow-network-connections docker` command as described in the [Prerequisites](#prerequisites) section.

Select **Save**

![Console - select zip file](console-50-upload-zip)

You're now ready to test your function.

#### Invoke the function 

Select the **Test** tab in the console and prepare a payload to send to your Lambda function. In this example, you've deployed the [HelloWorld](Exmaples.HelloWorld/README.md) example function. As explained, the function takes a `String` as input and returns a `String`. we will therefore create a test event with a JSON payload that contains a `String`.

Select **Create new event**. Enter an **Event name**. Enter `"Swift on Lambda"` as **Event JSON**. Note that the payload must be a valid JSON document, hence we use surrounding double quotes (`"`).

Select **Test** on the upper right side of the screen.

![Console - prepare test event](console-60-prepare-test-event)

The response of the invocation and additional meta data appear in the green section of the page.

You can see the response from the Swift code: `Hello Swift on Lambda`.

The function consumed 109.60ms of execution time, out of this 83.72ms where spent to initialize this new runtime. This initialization time is known as Lambda cold start time.

> Lambda cold start time refers to the initial delay that occurs when a Lambda function is invoked for the first time or after being idle for a while. Cold starts happen because AWS needs to provision and initialize a new container, load your code, and start your runtime environment (in this case, the Swift runtime). This delay is particularly noticeable for the first invocation, but subsequent invocations (known as "warm starts") are typically much faster because the container and runtime are already initialized and ready to process requests. Cold starts are an important consideration when architecting serverless applications, especially for latency-sensitive workloads. Usually, compiled languages, such as Swift, Go, and Rust, have shorter cold start times compared to interpreted languages, such as Python, Java, Ruby, and Node.js.

```text

![Console - view invocation result](console-70-view-invocation-response)

Select **Test** to invoke the function again with the same payload. 

Observe the results. No initialization time is reported because the Lambda execution environment was ready after the first invocation. The runtime duration of the second invocation is 1.12ms.

```text
REPORT RequestId: f789fbb6-10d9-4ba3-8a84-27aa283369a2	Duration: 1.12 ms	Billed Duration: 2 ms	Memory Size: 128 MB	Max Memory Used: 26 MB	
```

AWS lambda charges usage per number of invocations and the CPU time, rounded to the next millisecond. AWS Lambda offers a generous free-tier of 1 million invocation each month and 400,000 GB-seconds of compute time per month. See [Lambda pricing](https://aws.amazon.com/lambda/pricing/) for the details.

#### Delete the function

When you're finished with testing, you can delete the Lambda function and the IAM execution role that the console created automatically.

While you are on the `HelloWorld` function page in the AWS console, select **Actions**, then **Delete function** in the menu on the top-right part of the page.

![Console - delete function](console-80-delete-function)

Then, navigate to the IAM section of the AWS console. Select **Roles** on the right-side menu and search for `HelloWorld`. The console appended some random characters to role name. The name you see on your console is different that the one on the screenshot.

Select the `HelloWorld-role-xxxx` role and select **Delete**. Confirm the deletion by entering the role name again, and select **Delete** on the confirmation box.

![Console - delete IAM role](console-80-delete-role)

### Deploy your Lambda function with the AWS Command Line Interface (CLI)

You can deploy your Lambda function using the AWS Command Line Interface (CLI). The CLI is a unified tool to manage your AWS services from the command line and automate your operations through scripts. The CLI is available for Windows, macOS, and Linux. Follow the [installation](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) and [configuration](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-quickstart.html) instructions in the AWS CLI User Guide.

In this example, we're building the HelloWorld example from the [Examples](https://github.com/awslabs/swift-aws-lambda-runtime/tree/main/Examples) directory.

#### Create the function 

To create a function, you must first create the function execution role and define the permission. Then, you create the function with the `create-function` command.

The command assumes you've already created the ZIP file with the `swift package archive --allow-network-connections docker` command, as described in the [Prerequisites](#prerequisites) section.
 
```sh
# enter your AWS Account ID 
export AWS_ACCOUNT_ID=123456789012

# Allow the Lambda service to assume the execution role
cat <<EOF > assume-role-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "lambda.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF

# Create the execution role
aws iam create-role \
--role-name lambda_basic_execution \
--assume-role-policy-document file://assume-role-policy.json

# create permissions to associate with the role
cat <<EOF > permissions.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": "arn:aws:logs:*:*:*"
        }
    ]
}
EOF

# Attach the permissions to the role
aws iam put-role-policy \
--role-name lambda_basic_execution \
--policy-name lambda_basic_execution_policy \
--policy-document file://permissions.json

# Create the Lambda function
aws lambda create-function \
--function-name MyLambda \
--zip-file fileb://.build/plugins/AWSLambdaPackager/outputs/AWSLambdaPackager/MyLambda/MyLambda.zip \
--runtime provided.al2 \
--handler provided  \
--architectures arm64 \
--role arn:aws:iam::${AWS_ACCOUNT_ID}:role/lambda_basic_execution
```

The `--architectures` flag is only required when you build the binary on an Apple Silicon machine (Apple M1 or more recent). It defaults to `x64`.

To update the function, use the `update-function-code` command after you've recompiled and archived your code again with the `swift package archive` command.

```sh
aws lambda update-function-code \
--function-name MyLambda \
--zip-file fileb://.build/plugins/AWSLambdaPackager/outputs/AWSLambdaPackager/MyLambda/MyLambda.zip
```

#### Invoke the function 

Use the `invoke-function` command to invoke the function. You can pass a well-formed JSON payload as input to the function. The payload must be encoded in base64. The CLI returns the status code and stores the response in a file.

```sh
# invoke the function
aws lambda invoke \
--function-name MyLambda \
--payload $(echo \"Swift Lambda function\" | base64)  \
out.txt

# show the response
cat out.txt

# delete the response file
rm out.txt
```

#### Delete the function

To cleanup, first delete the Lambda funtion, then delete the IAM role.

```sh
# delete the Lambda function
aws lambda delete-function --function-name MyLambda

# delete the IAM policy attached to the role
aws iam delete-role-policy --role-name lambda_basic_execution --policy-name lambda_basic_execution_policy

# delete the IAM role
aws iam delete-role --role-name lambda_basic_execution
```

### Deploy your Lambda function with AWS Serverless Application Model (SAM)

AWS Serverless Application Model (SAM) is an open-source framework for building serverless applications. It provides a simplified way to define the Amazon API Gateway APIs, AWS Lambda functions, and Amazon DynamoDB tables needed by your serverless application. You can define your serverless application in a single file, and SAM will use it to deploy your function and all its dependencies.

To use SAM, you need to [install the SAM CLI](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/serverless-sam-cli-install.html) on your machine. The SAM CLI provides a set of commands to package, deploy, and manage your serverless applications.

Use SAM when you want to deploy more than a Lambda function. SAM helps you to create additional resources like an API Gateway, an S3 bucket, or a DynamoDB table, and manage the permissions between them.

#### Create the function

We assume your Swift function is compiled and packaged, as described in the [Prerequisites](#prerequisites) section.

When using SAM, you describe the infrastructure you want to deploy in a YAML file. The file contains the definition of the Lambda function, the IAM role, and the permissions needed by the function. The SAM CLI uses this file to package and deploy your function.

You can create a SAM template to define a REST API implemented by AWS API Gateway and a Lambda function with the following command

```sh
cat <<EOF > template.yaml
AWSTemplateFormatVersion: '2010-09-09'
Transform: AWS::Serverless-2016-10-31
Description: SAM Template for APIGateway Lambda Example

Resources:
  # Lambda function
  APIGatewayLambda:
    Type: AWS::Serverless::Function
    Properties:
      # the directory name and ZIP file names depends on the Swift executable target name
      CodeUri: .build/plugins/AWSLambdaPackager/outputs/AWSLambdaPackager/APIGatewayLambda/APIGatewayLambda.zip
      Timeout: 60
      Handler: swift.bootstrap  # ignored by the Swift runtime
      Runtime: provided.al2
      MemorySize: 128
      Architectures:
        - arm64
      # The events that will trigger this function  
      Events:
        HttpApiEvent:
          Type: HttpApi # AWS API Gateway v2

Outputs:
  # display API Gateway endpoint
  APIGatewayEndpoint:
    Description: "API Gateway endpoint URI"
    Value: !Sub "https://${ServerlessHttpApi}.execute-api.${AWS::Region}.amazonaws.com"
EOF
```

In this example, the Lambda function must accept an APIGateway v2 JSON payload as input parameter and return a valid APIGAteway v2 JSON response. See the example code in the [APIGateway example README file](https://github.com/awslabs/swift-aws-lambda-runtime/blob/main/Examples/APIGateway/README.md).

To deploy the function with SAM, use the `sam deploy` command. The very first time you deploy a function, you should use the `--guided` flag to configure the deployment. The command will ask you a series of questions to configure the deployment.

Here is the command to deploy the function with SAM:

```sh
# start the first deployment 
sam deploy --guided 

Configuring SAM deploy
======================

        Looking for config file [samconfig.toml] :  Not found

        Setting default arguments for 'sam deploy'
        =========================================
        Stack Name [sam-app]: APIGatewayLambda
        AWS Region [us-east-1]: 
        #Shows you resources changes to be deployed and require a 'Y' to initiate deploy
        Confirm changes before deploy [y/N]: n
        #SAM needs permission to be able to create roles to connect to the resources in your template
        Allow SAM CLI IAM role creation [Y/n]: y
        #Preserves the state of previously provisioned resources when an operation fails
        Disable rollback [y/N]: n
        APIGatewayLambda has no authentication. Is this okay? [y/N]: y
        Save arguments to configuration file [Y/n]: y
        SAM configuration file [samconfig.toml]: 
        SAM configuration environment [default]: 

        Looking for resources needed for deployment:

(redacted for brevity)

CloudFormation outputs from deployed stack
--------------------------------------------------------------------------------
Outputs                                                                                                                                         
--------------------------------------------------------------------------------
Key                 APIGatewayEndpoint                                                                                                          
Description         API Gateway endpoint URI"                                                                                                    
Value               https://59i4uwbuj2.execute-api.us-east-1.amazonaws.com                                                                      
--------------------------------------------------------------------------------


Successfully created/updated stack - APIGAtewayLambda in us-east-1        
```

To update your function or any other AWS service defined in your YAML file, you can use the `sam deploy` command without the `--guided` flag.

#### Invoke the function

SAM allows you to invoke the function locally and remotely. 

Local invocations allows you to test your code before uploading it. It requires docker to run.

```sh
# First, generate a sample event
sam local generate-event apigateway http-api-proxy > event.json 

# Next, invoke the function locally
sam local invoke -e ./event.json

START RequestId: 3f5096c6-0fd3-4605-b03e-d46658e6b141 Version: $LATEST
END RequestId: 3134f067-9396-4f4f-bebb-3c63ef745803
REPORT RequestId: 3134f067-9396-4f4f-bebb-3c63ef745803  Init Duration: 0.04 ms  Duration: 38.38 msBilled Duration: 39 ms  Memory Size: 512 MB     Max Memory Used: 512 MB
{"body": "{\"version\":\"2.0\",\"routeKey\":\"$default\",\"rawPath\":\"\\/path\\/to\\/resource\",... REDACTED FOR BREVITY ...., "statusCode": 200, "headers": {"content-type": "application/json"}}
```

> If you've previously authenticated to Amazon ECR Public and your auth token has expired, you may receive an authentication error when attempting to do unauthenticated docker pulls from Amazon ECR Public. To resolve this issue, it may be necessary to run `docker logout public.ecr.aws` to avoid the error. This will result in an unauthenticated pull. For more information, see [Authentication issues](https://docs.aws.amazon.com/AmazonECR/latest/public/public-troubleshooting.html#public-troubleshooting-authentication). 

Remote invocations are done with the `sam remote invoke` command.

```sh
sam remote invoke \
    --stack-name APIGatewayLambda \
    --event-file ./event.json

Invoking Lambda Function APIGatewayLambda                                                         
START RequestId: ec8082c5-933b-4176-9c63-4c8fb41ca259 Version: $LATEST
END RequestId: ec8082c5-933b-4176-9c63-4c8fb41ca259
REPORT RequestId: ec8082c5-933b-4176-9c63-4c8fb41ca259  Duration: 6.01 ms       Billed Duration: 7 ms     Memory Size: 512 MB     Max Memory Used: 35 MB
{"body":"{\"stageVariables\":{\"stageVariable1\":\"value1\",\"stageVariable2\":\"value2\"},\"rawPath\":\"\\\/path\\\/to\\\/resource\",\"routeKey\":\"$default\",\"cookies\":[\"cookie1\",\"cookie2\"] ... REDACTED FOR BREVITY ... \"statusCode\":200,"headers":{"content-type":"application/json"}}    
```

SAM allows you to access the function logs from Amazon Cloudwatch.

```sh
sam logs --stack-name APIGatewayLambda

Access logging is disabled for HTTP API ID (g9m53sn7xa)                                           
2024/12/19/[$LATEST]4dd42d66282145a2964ff13dfcd5dc65 2024-12-19T10:16:25.593000 INIT_START Runtime Version: provided:al2.v75      Runtime Version ARN: arn:aws:lambda:us-east-1::runtime:4f3438ed7de2250cc00ea1260c3dc3cd430fad27835d935a02573b6cf07ceed8
2024/12/19/[$LATEST]4dd42d66282145a2964ff13dfcd5dc65 2024-12-19T10:16:25.715000 START RequestId: d8afa647-8361-4bce-a817-c57b92a060af Version: $LATEST
2024/12/19/[$LATEST]4dd42d66282145a2964ff13dfcd5dc65 2024-12-19T10:16:25.758000 END RequestId: d8afa647-8361-4bce-a817-c57b92a060af
2024/12/19/[$LATEST]4dd42d66282145a2964ff13dfcd5dc65 2024-12-19T10:16:25.758000 REPORT RequestId: d8afa647-8361-4bce-a817-c57b92a060af    Duration: 40.74 ms      Billed Duration: 162 ms Memory Size: 512 MB       Max Memory Used: 34 MB  Init Duration: 120.64 ms
2024/12/19/[$LATEST]4dd42d66282145a2964ff13dfcd5dc65 2024-12-19T10:17:10.343000 START RequestId: ec8082c5-933b-4176-9c63-4c8fb41ca259 Version: $LATEST
2024/12/19/[$LATEST]4dd42d66282145a2964ff13dfcd5dc65 2024-12-19T10:17:10.350000 END RequestId: ec8082c5-933b-4176-9c63-4c8fb41ca259
2024/12/19/[$LATEST]4dd42d66282145a2964ff13dfcd5dc65 2024-12-19T10:17:10.350000 REPORT RequestId: ec8082c5-933b-4176-9c63-4c8fb41ca259    Duration: 6.01 ms       Billed Duration: 7 ms   Memory Size: 512 MB       Max Memory Used: 35 MB
```

You can also tail the logs with the `-t, --tail` flag.

#### Delete the function

SAM allows you to delete your function and all infrastructure that is defined in the YAML template with just one command.

```sh
sam delete

Are you sure you want to delete the stack APIGatewayLambda in the region us-east-1 ? [y/N]: y
Are you sure you want to delete the folder APIGatewayLambda in S3 which contains the artifacts? [y/N]: y
- Deleting S3 object with key APIGatewayLambda/1b5a27c048549382462bd8ea589f7cfe           
- Deleting S3 object with key APIGatewayLambda/396d2c434ecc24aaddb670bd5cca5fe8.template  
- Deleting Cloudformation stack APIGatewayLambda

Deleted successfully
```

### Deploy your Lambda function with the AWS Cloud Development Kit (CDK)

The AWS Cloud Development Kit is an open-source software development framework to define cloud infrastructure in code and provision it through AWS CloudFormation. The CDK provides high-level constructs that preconfigure AWS resources with best practices, and you can use familiar programming languages like TypeScript, Javascript, Python, Java, C#, and Go to define your infrastructure.

To use the CDK, you need to [install the CDK CLI](https://docs.aws.amazon.com/cdk/v2/guide/getting_started.html) on your machine. The CDK CLI provides a set of commands to manage your CDK projects.

Use the CDK when you want to define your infrastructure in code and manage the deployment of your Lambda function and other AWS services.

This example deploys the [APIGateway]((https://github.com/awslabs/swift-aws-lambda-runtime/blob/main/Examples/APIGateway/) example code.  It comprises a Lambda function that implements a REST API and an API Gateway to expose the function over HTTPS.

#### Create a CDK project

To create a new CDK project, use the `cdk init` command. The command creates a new directory with the project structure and the necessary files to define your infrastructure.

```sh
# In your Swift Lambda project folder
mkdir infra && cd infra
cdk init app --language typescript
```

In this example, the code to create a Swift Lambda function with the CDK is written in TypeScript. The following code creates a new Lambda function with the `swift` runtime.

It requires the `@aws-cdk/aws-lambda` package to define the Lambda function. You can install the dependency with the following command:

```sh
npm install aws-cdk-lib constructs
```

Then, in the lib folder, create a new file named `swift-lambda-stack.ts` with the following content:

```typescript
import * as cdk from 'aws-cdk-lib';
import * as lambda from 'aws-cdk-lib/aws-lambda';

export class LambdaApiStack extends cdk.Stack {
  constructor(scope: cdk.App, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Create the Lambda function
    const lambdaFunction = new lambda.Function(this, 'SwiftLambdaFunction', {
      runtime: lambda.Runtime.PROVIDED_AL2,
      architecture: lambda.Architecture.ARM_64,
      handler: 'bootstrap',
      code: lambda.Code.fromAsset('../.build/plugins/AWSLambdaPackager/outputs/AWSLambdaPackager/APIGatewayLambda/APIGatewayLambda.zip'),
      memorySize: 128,
      timeout: cdk.Duration.seconds(30),
      environment: {
        LOG_LEVEL: 'debug',
      },
    });
 }
}    
```
The code assumes you already built and packaged the APIGateway Lambda function with the `swift package archive --allow-network-connections docker` command, as described in the [Prerequisites](#prerequisites) section.

You can write code to add an API Gateway to invoke your Lambda function. The following code creates an HTTP API Gateway that triggers the Lambda function.

```typescript
// in the import section at the top
import * as apigateway from 'aws-cdk-lib/aws-apigatewayv2';
import { HttpLambdaIntegration } from 'aws-cdk-lib/aws-apigatewayv2-integrations';

// in the constructor, after having created the Lambda function
// ...

    // Create the API Gateway
    const httpApi = new apigateway.HttpApi(this, 'HttpApi', {
      defaultIntegration: new HttpLambdaIntegration({
        handler: lambdaFunction,
      }),
    });

    // Output the API Gateway endpoint
    new cdk.CfnOutput(this, 'APIGatewayEndpoint', {
      value: httpApi.url!,
    });

// ...    
```

#### Deploy the infrastructure 

To deploy the infrastructure, type the following commands.

```sh
# Change to the infra directory
cd infra

# Install the dependencies (only before the first deployment)
npm install 

# Deploy the infrastructure
cdk deploy

✨  Synthesis time: 2.88s
... redacted for brevity ...
Do you wish to deploy these changes (y/n)? y
... redacted for brevity ...
 ✅  LambdaApiStack

✨  Deployment time: 42.96s

Outputs:
LambdaApiStack.ApiUrl = https://tyqnjcawh0.execute-api.eu-central-1.amazonaws.com/
Stack ARN:
arn:aws:cloudformation:eu-central-1:012345678901:stack/LambdaApiStack/e0054390-be05-11ef-9504-065628de4b89

✨  Total time: 45.84s
```

#### Invoke your Lambda function

To invoke the Lambda function, use this `curl` command line.

```bash
curl https://tyqnjcawh0.execute-api.eu-central-1.amazonaws.com
```

Be sure to replace the URL with the API Gateway endpoint returned in the previous step.

This should print a JSON similar to 

```bash 
{"version":"2.0","rawPath":"\/","isBase64Encoded":false,"rawQueryString":"","headers":{"user-agent":"curl\/8.7.1","accept":"*\/*","host":"a5q74es3k2.execute-api.us-east-1.amazonaws.com","content-length":"0","x-amzn-trace-id":"Root=1-66fb0388-691f744d4bd3c99c7436a78d","x-forwarded-port":"443","x-forwarded-for":"81.0.0.43","x-forwarded-proto":"https"},"requestContext":{"requestId":"e719cgNpoAMEcwA=","http":{"sourceIp":"81.0.0.43","path":"\/","protocol":"HTTP\/1.1","userAgent":"curl\/8.7.1","method":"GET"},"stage":"$default","apiId":"a5q74es3k2","time":"30\/Sep\/2024:20:01:12 +0000","timeEpoch":1727726472922,"domainPrefix":"a5q74es3k2","domainName":"a5q74es3k2.execute-api.us-east-1.amazonaws.com","accountId":"012345678901"}
```

If you have `jq` installed, you can use it to pretty print the output.

```bash
curl -s  https://tyqnjcawh0.execute-api.eu-central-1.amazonaws.com | jq   
{
  "version": "2.0",
  "rawPath": "/",
  "requestContext": {
    "domainPrefix": "a5q74es3k2",
    "stage": "$default",
    "timeEpoch": 1727726558220,
    "http": {
      "protocol": "HTTP/1.1",
      "method": "GET",
      "userAgent": "curl/8.7.1",
      "path": "/",
      "sourceIp": "81.0.0.43"
    },
    "apiId": "a5q74es3k2",
    "accountId": "012345678901",
    "requestId": "e72KxgsRoAMEMSA=",
    "domainName": "a5q74es3k2.execute-api.us-east-1.amazonaws.com",
    "time": "30/Sep/2024:20:02:38 +0000"
  },
  "rawQueryString": "",
  "routeKey": "$default",
  "headers": {
    "x-forwarded-for": "81.0.0.43",
    "user-agent": "curl/8.7.1",
    "host": "a5q74es3k2.execute-api.us-east-1.amazonaws.com",
    "accept": "*/*",
    "x-amzn-trace-id": "Root=1-66fb03de-07533930192eaf5f540db0cb",
    "content-length": "0",
    "x-forwarded-proto": "https",
    "x-forwarded-port": "443"
  },
  "isBase64Encoded": false
}
```

#### Delete the infrastructure

When done testing, you can delete the infrastructure with this command.

```bash
cdk destroy

Are you sure you want to delete: LambdaApiStack (y/n)? y
LambdaApiStack: destroying... [1/1]
... redacted for brevity ...
 ✅  LambdaApiStack: destroyed
```

### Third-party tools

We welcome contributions to this section. If you have experience deploying Swift Lambda functions with third-party tools like Serverless Framework, Terraform, or Pulumi, please share your knowledge with the community.

### ⚠️ Security and Reliability Notice

These are example applications for demonstration purposes. When deploying such infrastructure in production environments, we strongly encourage you to follow these best practices for improved security and resiliency:

- Enable access logging on API Gateway ([documentation](https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-logging.html))
- Ensure that AWS Lambda function is configured for function-level concurrent execution limit ([concurrency documentation](https://docs.aws.amazon.com/lambda/latest/dg/lambda-concurrency.html), [configuration guide](https://docs.aws.amazon.com/lambda/latest/dg/configuration-concurrency.html))
- Check encryption settings for Lambda environment variables ([documentation](https://docs.aws.amazon.com/lambda/latest/dg/configuration-envvars-encryption.html))
- Ensure that AWS Lambda function is configured for a Dead Letter Queue (DLQ) ([documentation](https://docs.aws.amazon.com/lambda/latest/dg/invocation-async-retain-records.html#invocation-dlq))
- Ensure that AWS Lambda function is configured inside a VPC when it needs to access private resources ([documentation](https://docs.aws.amazon.com/lambda/latest/dg/configuration-vpc.html), [code example](https://github.com/awslabs/swift-aws-lambda-runtime/tree/main/Examples/ServiceLifecycle%2BPostgres))