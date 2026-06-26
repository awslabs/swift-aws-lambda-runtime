# API Gateway and Cloud Development Kit

This is a simple example of an AWS Lambda function invoked through an Amazon API Gateway and deployed with the Cloud Development Kit (CDK).

## Code 

The Lambda function takes all HTTP headers it receives as input and returns them as output. See the [API Gateway example](Examples/APIGateway/README.md) for a complete description of the code.

## Build & Package 

To build the package, type the following commands.

```bash
swift build
swift package --allow-network-connections docker lambda-build
```

If there is no error, there is a ZIP file ready to deploy. 
The ZIP file is located at `.build/plugins/AWSLambdaBuilder/outputs/AWSLambdaBuilder/APIGatewayLambda/APIGatewayLambda.zip`

## Deploy

>[NOTE]
>Before deploying the infrastructure, you need to have NodeJS and the AWS CDK installed and configured.
>For more information, see the [AWS CDK documentation](https://docs.aws.amazon.com/cdk/v2/guide/getting_started.html).

To deploy the infrastructure, type the following commands.

```sh
# Change to the infra directory
cd infra

# Install the dependencies (only before the first deployment)
npm install 

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
arn:aws:cloudformation:eu-central-1:401955065246:stack/LambdaApiStack/e0054390-be05-11ef-9504-065628de4b89

✨  Total time: 45.84s
```

## Invoke your Lambda function

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

## Undeploy

When done testing, you can delete the infrastructure with this command.

```bash
cdk destroy

Are you sure you want to delete: LambdaApiStack (y/n)? y
LambdaApiStack: destroying... [1/1]
... redacted for brevity ...
 ✅  LambdaApiStack: destroyed
```

## ⚠️ Security and Reliability Notice

These are example applications for demonstration purposes. When deploying such infrastructure in production environments, we strongly encourage you to follow these best practices for improved security and resiliency:

- Enable access logging on API Gateway ([documentation](https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-logging.html))
- Ensure that AWS Lambda function is configured for function-level concurrent execution limit ([concurrency documentation](https://docs.aws.amazon.com/lambda/latest/dg/lambda-concurrency.html), [configuration guide](https://docs.aws.amazon.com/lambda/latest/dg/configuration-concurrency.html))
- Check encryption settings for Lambda environment variables ([documentation](https://docs.aws.amazon.com/lambda/latest/dg/configuration-envvars-encryption.html))
- Ensure that AWS Lambda function is configured for a Dead Letter Queue (DLQ) ([documentation](https://docs.aws.amazon.com/lambda/latest/dg/invocation-async-retain-records.html#invocation-dlq))
- Ensure that AWS Lambda function is configured inside a VPC when it needs to access private resources ([documentation](https://docs.aws.amazon.com/lambda/latest/dg/configuration-vpc.html), [code example](https://github.com/awslabs/swift-aws-lambda-runtime/tree/main/Examples/ServiceLifecycle%2BPostgres))