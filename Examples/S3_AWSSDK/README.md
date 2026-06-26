# List Amazon S3 Buckets with the AWS SDK for Swift 

This is a simple example of an AWS Lambda function that uses the [AWS SDK for Swift](https://github.com/awslabs/aws-sdk-swift) to read data from Amazon S3.

## Code 

The Lambda function reads all bucket names from your AWS account and returns them as a String.

The code creates a `LambdaRuntime` struct. In it's simplest form, the initializer takes a function as argument. The function is the handler that will be invoked when the API Gateway receives an HTTP request.

The handler is `(event: APIGatewayV2Request, context: LambdaContext) -> APIGatewayV2Response`. The function takes two arguments:
- the event argument is a `APIGatewayV2Request`. It is the parameter passed by the API Gateway. It contains all data passed in the HTTP request and some meta data.
- the context argument is a `Lambda Context`. It is a description of the runtime context.

The function must return a `APIGatewayV2Response`.

`APIGatewayV2Request` and `APIGatewayV2Response` are defined in the [Swift AWS Lambda Events](https://github.com/awslabs/swift-aws-lambda-events) library.

The handler creates an S3 client and `ListBucketsInput` object. It passes the input object to the client and receives an output response.
It then extracts the list of bucket names from the output and creates a `\n`-separated list of names, as a `String`

## Build & Package 

To build the package, type the following commands.

```bash
swift build
swift package --allow-network-connections docker lambda-build
```

If there is no error, there is a ZIP file ready to deploy. 
The ZIP file is located at `.build/plugins/AWSLambdaBuilder/outputs/AWSLambdaBuilder/AWSSDKExample/AWSSDKExample.zip`

## Deploy

The deployment must include the Lambda function and an API Gateway. We use the [Serverless Application Model (SAM)](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/what-is-sam.html) to deploy the infrastructure.

**Prerequisites** : Install the [SAM CLI](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html)

The example directory contains a file named `template.yaml` that describes the deployment.

To actually deploy your Lambda function and create the infrastructure, type the following `sam` command.

```bash
sam deploy \
--resolve-s3 \
--template-file template.yaml \
--stack-name AWSSDKExample \
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

To invoke the Lambda function, use this `curl` command line.

```bash
curl https://a5q74es3k2.execute-api.us-east-1.amazonaws.com 
```

Be sure to replace the URL with the API Gateway endpoint returned in the previous step.

This should print text similar to 

```bash 
my_bucket_1
my_bucket_2
...
```

## Delete the infrastructure

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