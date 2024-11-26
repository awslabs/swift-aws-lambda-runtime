# List Amazon S3 Buckets with Soto 

This is a simple example of an AWS Lambda function that uses the [Soto SDK for AWS](https://github.com/soto-project/soto) to read data from Amazon S3.

## Code 

The Lambda function reads all bucket names from your AWS account and returns them as a String.

The code creates a `LambdaRuntime` struct. In it's simplest form, the initializer takes a function as argument. The function is the handler that will be invoked when the API Gateway receives an HTTP request.

The handler is `(event: APIGatewayV2Request, context: LambdaContext) -> APIGatewayV2Response`. The function takes two arguments:
- the event argument is a `APIGatewayV2Request`. It is the parameter passed by the API Gateway. It contains all data passed in the HTTP request and some meta data.
- the context argument is a `Lambda Context`. It is a description of the runtime context.

The function must return a `APIGatewayV2Response`.

`APIGatewayV2Request` and `APIGatewayV2Response` are defined in the [Swift AWS Lambda Events](https://github.com/swift-server/swift-aws-lambda-events) library.

The handler creates two clients : an AWS client that manages the communication with AWS API and and the S3 client that expose the S3 API. Then, the handler calls `listBuckets()` on the S3 client and receives an output response.
Finally, the handler extracts the list of bucket names from the output to create a `\n`-separated list of names, as a `String`.

## Build & Package 

To build the package, type the following command.

```bash
swift build
swift package archive --allow-network-connections docker
```

If there is no error, there is a ZIP file ready to deploy. 
The ZIP file is located at `.build/plugins/AWSLambdaPackager/outputs/AWSLambdaPackager/SotoExample/SotoExample.zip`

## Deploy

The deployment must include the Lambda function and an API Gateway. We use the [Serverless Application Model (SAM)](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/what-is-sam.html) to deploy the infrastructure.

**Prerequisites** : Install the [SAM CLI](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html)

The example directory contains a file named `template.yaml` that describes the deployment.

To actually deploy your Lambda function and create the infrastructure, type the following `sam` command.

```bash
sam deploy \
--resolve-s3 \
--template-file template.yaml \
--stack-name SotoExample \
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