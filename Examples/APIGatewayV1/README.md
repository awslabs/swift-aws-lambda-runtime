# REST API Gateway 

This is a simple example of an AWS Lambda function invoked through an Amazon API Gateway V1.

> [!NOTE]
> This example uses the API Gateway V1 `Rest Api` endpoint type, whereas the [API Gateway V2](https://github.com/awslabs/swift-aws-lambda-runtime/tree/main/Examples/APIGateway) example uses the `HttpApi` endpoint type. For more information, see [Choose between REST APIs and HTTP APIs](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-vs-rest.html).

## Code 

The Lambda function takes all HTTP headers it receives as input and returns them as output.

The code creates a `LambdaRuntime` struct. In it's simplest form, the initializer takes a function as argument. The function is the handler that will be invoked when the API Gateway receives an HTTP request.

The handler is `(event: APIGatewayRequest, context: LambdaContext) -> APIGatewayResponse`. The function takes two arguments:
- the event argument is a `APIGatewayRequest`. It is the parameter passed by the API Gateway. It contains all data passed in the HTTP request and some meta data.
- the context argument is a `Lambda Context`. It is a description of the runtime context.

The function must return a `APIGatewayResponse`.

`APIGatewayRequest` and `APIGatewayResponse` are defined in the [Swift AWS Lambda Events](https://github.com/awslabs/swift-aws-lambda-events) library.

## Build & Package 

To build the package, type the following commands.

```bash
swift build
swift package --allow-network-connections docker lambda-build
```

If there is no error, there is a ZIP file ready to deploy. 
The ZIP file is located at `.build/plugins/AWSLambdaBuilder/outputs/AWSLambdaBuilder/APIGatewayLambda/APIGatewayLambda.zip`

## Deploy

The deployment must include the Lambda function and the API Gateway. We use the [Serverless Application Model (SAM)](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/what-is-sam.html) to deploy the infrastructure.

**Prerequisites** : Install the [SAM CLI](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html)

The example directory contains a file named `template.yaml` that describes the deployment.

To actually deploy your Lambda function and create the infrastructure, type the following `sam` command.

```bash
sam deploy \
--resolve-s3 \
--template-file template.yaml \
--stack-name APIGatewayLambda \
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

This should print a JSON similar to 

```bash
{"httpMethod":"GET","queryStringParameters":{},"isBase64Encoded":false,"resource":"\/","path":"\/","headers":{"X-Forwarded-Port":"3000","X-Forwarded-Proto":"http","User-Agent":"curl\/8.7.1","Host":"localhost:3000","Accept":"*\/*"},"requestContext":{"resourcePath":"\/","identity":{"sourceIp":"127.0.0.1","userAgent":"Custom User Agent String"},"httpMethod":"GET","resourceId":"123456","accountId":"123456789012","apiId":"1234567890","requestId":"a9d2db08-8364-4da4-8237-8912bf8148c8","domainName":"localhost:3000","stage":"Prod","path":"\/"},"multiValueQueryStringParameters":{},"pathParameters":{},"multiValueHeaders":{"Accept":["*\/*"],"Host":["localhost:3000"],"X-Forwarded-Port":["3000"],"User-Agent":["curl\/8.7.1"],"X-Forwarded-Proto":["http"]},"stageVariables":{}}
```

If you have `jq` installed, you can use it to pretty print the output.

```bash
curl -s  https://a5q74es3k2.execute-api.us-east-1.amazonaws.com | jq   
{
  "stageVariables": {},
  "queryStringParameters": {},
  "multiValueHeaders": {
    "Accept": [
      "*/*"
    ],
    "User-Agent": [
      "curl/8.7.1"
    ],
    "X-Forwarded-Proto": [
      "http"
    ],
    "Host": [
      "localhost:3000"
    ],
    "X-Forwarded-Port": [
      "3000"
    ]
  },
  "pathParameters": {},
  "isBase64Encoded": false,
  "path": "/",
  "requestContext": {
    "apiId": "1234567890",
    "stage": "Prod",
    "httpMethod": "GET",
    "domainName": "localhost:3000",
    "requestId": "a9d2db08-8364-4da4-8237-8912bf8148c8",
    "identity": {
      "userAgent": "Custom User Agent String",
      "sourceIp": "127.0.0.1"
    },
    "resourceId": "123456",
    "path": "/",
    "resourcePath": "/",
    "accountId": "123456789012"
  },
  "multiValueQueryStringParameters": {},
  "resource": "/",
  "headers": {
    "Accept": "*/*",
    "X-Forwarded-Proto": "http",
    "X-Forwarded-Port": "3000",
    "Host": "localhost:3000",
    "User-Agent": "curl/8.7.1"
  },
  "httpMethod": "GET"
}
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