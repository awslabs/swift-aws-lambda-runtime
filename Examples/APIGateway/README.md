# API Gateway 

This is a simple example of an AWS Lambda function invoked through an Amazon API Gateway.

## Code 

The Lambda function takes all HTTP headers it receives as input and returns them as output.

The code creates a `LambdaRuntime` struct. In it's simplest form, the initializer takes a function as argument. The function is the handler that will be invoked when the API Gateway receives an HTTP request.

The handler is `(event: APIGatewayV2Request, context: LambdaContext) -> APIGatewayV2Response`. The function takes two arguments:
- the event argument is a `APIGatewayV2Request`. It is the parameter passed by the API Gateway. It contains all data passed in the HTTP request and some meta data.
- the context argument is a `Lambda Context`. It is a description of the runtime context.

The function must return a `APIGatewayV2Response`.

`APIGatewayV2Request` and `APIGatewayV2Response` are defined in the [Swift AWS Lambda Events](https://github.com/swift-server/swift-aws-lambda-events) library.

## Build & Package 

To build the package, type the following commands.

```bash
swift build
swift package archive --allow-network-access docker
```

If there is no error, there is a ZIP file ready to deploy. 
The ZIP file is located at `.build/plugins/AWSLambdaPackager/outputs/AWSLambdaPackager/MyLambda/MyLambda.zip`

## Deploy

The deployment must include the Lambda function and the API Gateway. We use the [Serverless Application Model (SAM)](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/what-is-sam.html) to deploy the infrastructure.

**Prerequisites** : Install the [SAM CLI](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html)

The example directory contains a file named `template.yaml` that describes the deployment.

To actually deploy your Lambda function and create the infrastructure, type the following `sam` command.

```bash
sam deploy \
----resolve-s3 \
--template-file template.yaml \
--stack-name MyLambda \
--capabilities CAPABILITY_IAM 
```

At the end of the deployment, the script lists the API Gateway endpoint.
The output is similar to this one.

```
-----------------------------------------------------------------------------------------------------------------------------
Outputs                                                                                                                     
-----------------------------------------------------------------------------------------------------------------------------
Key                 APIGAtewayEndpoint                                                                                      
Description         API Gateway endpoint UR"                                                                                
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
{"version":"2.0","rawPath":"\/","isBase64Encoded":false,"rawQueryString":"","headers":{"user-agent":"curl\/8.7.1","accept":"*\/*","host":"a5q74es3k2.execute-api.us-east-1.amazonaws.com","content-length":"0","x-amzn-trace-id":"Root=1-66fb0388-691f744d4bd3c99c7436a78d","x-forwarded-port":"443","x-forwarded-for":"81.0.0.43","x-forwarded-proto":"https"},"requestContext":{"requestId":"e719cgNpoAMEcwA=","http":{"sourceIp":"81.0.0.43","path":"\/","protocol":"HTTP\/1.1","userAgent":"curl\/8.7.1","method":"GET"},"stage":"$default","apiId":"a5q74es3k2","time":"30\/Sep\/2024:20:01:12 +0000","timeEpoch":1727726472922,"domainPrefix":"a5q74es3k2","domainName":"a5q74es3k2.execute-api.us-east-1.amazonaws.com","accountId":"012345678901"}
```

If you have `jq` installed, you can use it to pretty print the output.

```bash
curl -s  https://a5q74es3k2.execute-api.us-east-1.amazonaws.com | jq   
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

## Undeploy

When done testing, you can delete the infrastructure with this command.

```bash
sam delete 
```