# Lambda Authorizer with HTTPS API Gateway 

This is an example of a Lambda Authorizer function.  There are two Lambda functions in this example. The first one is the authorizer function. The second one is the business function. The business function is exposed through a REST API using the HTTPS API Gateway. The API Gateway is configured to use the authorizer function to implement a custom logic to authorize the requests. 

>[!NOTE]
> If your application is protected by JWT tokens, it's recommended to use [the native JWT authorizer provided by the API Gateway](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-jwt-authorizer.html). The Lambda authorizer is useful when you need to implement a custom authorization logic. See the [OAuth 2.0/JWT authorizer example for AWS SAM](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/serverless-controlling-access-to-apis-oauth2-authorizer.html) to learn how to use the native JWT authorizer with SAM.

## Code 

The authorizer function is a simple function that checks data received from the API Gateway. In this example, the API Gateway is configured to pass the content of the `Authorization` header to the authorizer Lambda function.

There are two possible responses from a Lambda Authorizer function: policy and simple. The policy response returns an IAM policy document that describes the permissions of the caller. The simple response returns a boolean value that indicates if the caller is authorized or not. You can read more about the two types of responses in the [Lambda authorizer response format](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-lambda-authorizer.html) section of the API Gateway documentation.

This example uses an authorizer that returns the simple response. The authorizer function is defined in the `Sources/AuthorizerLambda` directory. The business function is defined in the `Sources/APIGatewayLambda` directory.

## Build & Package 

To build the package, type the following commands.

```bash
swift build
swift package --allow-network-connections docker lambda-build
```

If there is no error, there are two ZIP files ready to deploy, one for the authorizer function and one for the business function.
The ZIP file are located under `.build/plugins/AWSLambdaBuilder/outputs/AWSLambdaBuilder`

## Deploy

The deployment must include the Lambda functions and the API Gateway. We use the [Serverless Application Model (SAM)](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/what-is-sam.html) to deploy the infrastructure.

**Prerequisites** : Install the [SAM CLI](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html)

The example directory contains a file named `template.yaml` that describes the deployment.

To actually deploy your Lambda function and create the infrastructure, type the following `sam` command.

```bash
sam deploy \
--resolve-s3 \
--template-file template.yaml \
--stack-name APIGatewayWithLambdaAuthorizer \
--capabilities CAPABILITY_IAM 
```

At the end of the deployment, the script lists the API Gateway endpoint.
The output is similar to this one.

```
-----------------------------------------------------------------------------------------------------------------------------
Outputs                                                                                                                     
-----------------------------------------------------------------------------------------------------------------------------
Key                 APIGatewayEndpoint                                                                                      
Description         API Gateway endpoint URI                                                                                
Value               https://a5q74es3k2.execute-api.us-east-1.amazonaws.com/demo                                                 
-----------------------------------------------------------------------------------------------------------------------------
```

## Invoke your Lambda function

To invoke the Lambda function, use this `curl` command line. Be sure to replace the URL with the API Gateway endpoint returned in the previous step.

When invoking the Lambda function without `Authorization` header, the response is a `401 Unauthorized` error.

```bash
curl -v https://a5q74es3k2.execute-api.us-east-1.amazonaws.com/demo
...
> GET /demo HTTP/2
> Host: 6sm6270j21.execute-api.us-east-1.amazonaws.com
> User-Agent: curl/8.7.1
> Accept: */*
> 
* Request completely sent off
< HTTP/2 401 
< date: Sat, 04 Jan 2025 14:03:02 GMT
< content-type: application/json
< content-length: 26
< apigw-requestid: D3bfpidOoAMESiQ=
< 
* Connection #0 to host 6sm6270j21.execute-api.us-east-1.amazonaws.com left intact
{"message":"Unauthorized"}
```

When invoking the Lambda function with the `Authorization` header, the response is a `200 OK` status code. Note that the Lambda Authorizer function is configured to accept any value in the `Authorization` header.

```bash
curl -v -H 'Authorization: 123' https://a5q74es3k2.execute-api.us-east-1.amazonaws.com/demo
...
> GET /demo HTTP/2
> Host: 6sm6270j21.execute-api.us-east-1.amazonaws.com
> User-Agent: curl/8.7.1
> Accept: */*
> Authorization: 123
> 
* Request completely sent off
< HTTP/2 200 
< date: Sat, 04 Jan 2025 14:04:43 GMT
< content-type: application/json
< content-length: 911
< apigw-requestid: D3bvRjJcoAMEaig=
< 
* Connection #0 to host 6sm6270j21.execute-api.us-east-1.amazonaws.com left intact
{"headers":{"x-forwarded-port":"443","x-forwarded-proto":"https","host":"6sm6270j21.execute-api.us-east-1.amazonaws.com","user-agent":"curl\/8.7.1","accept":"*\/*","content-length":"0","x-amzn-trace-id":"Root=1-67793ffa-05f1296f1a52f8a066180020","authorization":"123","x-forwarded-for":"81.49.207.77"},"routeKey":"ANY \/demo","version":"2.0","rawQueryString":"","isBase64Encoded":false,"queryStringParameters":{},"pathParameters":{},"rawPath":"\/demo","cookies":[],"requestContext":{"domainPrefix":"6sm6270j21","requestId":"D3bvRjJcoAMEaig=","domainName":"6sm6270j21.execute-api.us-east-1.amazonaws.com","stage":"$default","authorizer":{"lambda":{"abc1":"xyz1"}},"timeEpoch":1735999482988,"accountId":"401955065246","time":"04\/Jan\/2025:14:04:42 +0000","http":{"method":"GET","sourceIp":"81.49.207.77","path":"\/demo","userAgent":"curl\/8.7.1","protocol":"HTTP\/1.1"},"apiId":"6sm6270j21"},"stageVariables":{}}
```

## Undeploy

When done testing, you can delete the infrastructure with this command.

```bash
sam delete --stack-name APIGatewayWithLambdaAuthorizer
```

## ⚠️ Security and Reliability Notice

These are example applications for demonstration purposes. When deploying such infrastructure in production environments, we strongly encourage you to follow these best practices for improved security and resiliency:

- Enable access logging on API Gateway ([documentation](https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-logging.html))
- Ensure that AWS Lambda function is configured for function-level concurrent execution limit ([concurrency documentation](https://docs.aws.amazon.com/lambda/latest/dg/lambda-concurrency.html), [configuration guide](https://docs.aws.amazon.com/lambda/latest/dg/configuration-concurrency.html))
- Check encryption settings for Lambda environment variables ([documentation](https://docs.aws.amazon.com/lambda/latest/dg/configuration-envvars-encryption.html))
- Ensure that AWS Lambda function is configured for a Dead Letter Queue (DLQ) ([documentation](https://docs.aws.amazon.com/lambda/latest/dg/invocation-async-retain-records.html#invocation-dlq))
- Ensure that AWS Lambda function is configured inside a VPC when it needs to access private resources ([documentation](https://docs.aws.amazon.com/lambda/latest/dg/configuration-vpc.html), [code example](https://github.com/awslabs/swift-aws-lambda-runtime/tree/main/Examples/ServiceLifecycle%2BPostgres))