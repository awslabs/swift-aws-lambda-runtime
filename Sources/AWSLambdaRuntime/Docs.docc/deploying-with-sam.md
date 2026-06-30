# Deploy with AWS SAM

@Metadata {
    @PageKind(article)
    @PageColor(orange)
    @SupportedLanguage(swift)
    @PageImage(source: "lambda.png", alt: "AWS Lambda", purpose: icon)
}

Deploy your Swift Lambda function and its supporting resources with the AWS Serverless Application Model.

## Overview

AWS Serverless Application Model (SAM) is an open-source framework for building serverless applications. It provides a simplified way to define the Amazon API Gateway APIs, AWS Lambda functions, and Amazon DynamoDB tables needed by your serverless application. You can define your serverless application in a single file, and SAM will use it to deploy your function and all its dependencies.

To use SAM, you need to [install the SAM CLI](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/serverless-sam-cli-install.html) on your machine. The SAM CLI provides a set of commands to package, deploy, and manage your serverless applications.

Use SAM when you want to deploy more than a Lambda function. SAM helps you to create additional resources like an API Gateway, an S3 bucket, or a DynamoDB table, and manage the permissions between them.

> See <doc:deploying-prerequisites> for the AWS account, credentials, and build steps this article assumes.

## Create the function

We assume your Swift function is compiled and packaged, as described in <doc:deploying-prerequisites>.

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
      CodeUri: .build/plugins/AWSLambdaBuilder/outputs/AWSLambdaBuilder/APIGatewayLambda/APIGatewayLambda.zip
      Timeout: 60
      Handler: swift.bootstrap  # ignored by the Swift runtime
      Runtime: provided.al2023
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

In this example, the Lambda function must accept an APIGateway v2 JSON payload as input parameter and return a valid APIGAteway v2 JSON response. See the example code in the [APIGateway example README file](https://github.com/awslabs/swift-aws-lambda-runtime/blob/main/Examples/APIGatewayV2/README.md).

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

## Invoke the function

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

## Delete the function

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
