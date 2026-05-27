# Hummingbird Lambda

This is a simple example of an AWS Lambda function using the [Hummingbird](https://github.com/hummingbird-project/hummingbird) web framework, invoked through an Amazon API Gateway.

## Code 

The Lambda function uses Hummingbird's router to handle HTTP requests. It defines a simple GET endpoint at `/hello` that returns "Hello".

The code creates a `Router` with `AppRequestContext` (which is a type alias for `BasicLambdaRequestContext<APIGatewayV2Request>`). The router defines HTTP routes using Hummingbird's familiar syntax.

The `APIGatewayV2LambdaFunction` wraps the Hummingbird router to make it compatible with AWS Lambda and API Gateway V2 events.

`APIGatewayV2Request` is defined in the [Swift AWS Lambda Events](https://github.com/awslabs/swift-aws-lambda-events) library, and the Hummingbird Lambda integration is provided by the [Hummingbird Lambda](https://github.com/hummingbird-project/hummingbird-lambda) package.

## Build & Package 

To build the package, type the following commands.

```bash
swift build
swift package archive --allow-network-connections docker --base-docker-image swift:amazonlinux2023
```

If there is no error, there is a ZIP file ready to deploy. 
The ZIP file is located at `.build/plugins/AWSLambdaPackager/outputs/AWSLambdaPackager/HBLambda/HBLambda.zip`

## Deploy

The deployment must include the Lambda function and the API Gateway. We use the [Serverless Application Model (SAM)](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/what-is-sam.html) to deploy the infrastructure.

**Prerequisites** : Install the [SAM CLI](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html)

The example directory contains a file named `template.yaml` that describes the deployment.

To actually deploy your Lambda function and create the infrastructure, type the following `sam` command.

```bash
sam deploy \
--resolve-s3 \
--template-file template.yaml \
--stack-name HummingbirdLambda \
--capabilities CAPABILITY_IAM 
```

At the end of the deployment, the script lists the API Gateway endpoint.
The output is similar to this one.

```
-----------------------------------------------------------------------------------------------------------------------------
Outputs                                                                                                                     
-----------------------------------------------------------------------------------------------------------------------------
Key                 APIGatewayEndpoint                                                                                      
Description         API Gateway endpoint URL"                                                                                
Value               https://a5q74es3k2.execute-api.us-east-1.amazonaws.com                                                  
-----------------------------------------------------------------------------------------------------------------------------
```

## Invoke your Lambda function

To invoke the Lambda function, use this `curl` command line to call the `/hello` endpoint.

```bash
curl https://a5q74es3k2.execute-api.us-east-1.amazonaws.com/hello
```

Be sure to replace the URL with the API Gateway endpoint returned in the previous step.

This should print:

```bash 
Hello
```

## Undeploy

When done testing, you can delete the infrastructure with this command.

```bash
sam delete 
```

## ⚠️ Security and Reliability Notice

These are example applications for demonstration purposes. When deploying such infrastructure in production environments, we strongly encourage you to follow these best practices for improved security and resiliency:

- Enable access logging on API Gateway ([documentation](https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-logging.html))
- Ensure that AWS Lambda function is configured for function-level concurrent execution limit ([concurrency documentation](https://docs.aws.amazon.com/lambda/latest/dg/lambda-concurrency.html), [configuration guide](https://docs.aws.amazon.com/lambda/latest/dg/configuration-concurrency.html))
- Check encryption settings for Lambda environment variables ([documentation](https://docs.aws.amazon.com/lambda/latest/dg/configuration-envvars-encryption.html))
- Ensure that AWS Lambda function is configured for a Dead Letter Queue (DLQ) ([documentation](https://docs.aws.amazon.com/lambda/latest/dg/invocation-async-retain-records.html#invocation-dlq))
- Ensure that AWS Lambda function is configured inside a VPC when it needs to access private resources ([documentation](https://docs.aws.amazon.com/lambda/latest/dg/configuration-vpc.html), [code example](https://github.com/awslabs/swift-aws-lambda-runtime/tree/main/Examples/ServiceLifecycle%2BPostgres))