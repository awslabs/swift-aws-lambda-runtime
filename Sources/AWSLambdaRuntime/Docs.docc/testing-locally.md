# Testing your function locally

@Metadata {
    @PageKind(article)
    @PageColor(orange)
    @SupportedLanguage(swift)
    @PageImage(source: "lambda.png", alt: "AWS Lambda", purpose: icon)
}

Run and invoke your Lambda function on your local machine before deploying it to AWS.

## Overview

Before deploying your code to AWS Lambda, you can test it locally by running the executable target on your machine.

```sh
swift run
```

When not running inside a Lambda execution environment, the runtime starts a local HTTP server listening on port 7000. You can invoke your local function by sending an HTTP POST request to `http://127.0.0.1:7000/invoke`.

The request must include the JSON payload your function expects as an `event`. You can create a text file with the JSON payload documented by AWS or captured from a trace. In the example below, we use [the API Gateway v2 JSON payload from the documentation](https://docs.aws.amazon.com/lambda/latest/dg/services-apigateway.html#apigateway-example-event), saved as `events/create-session.json`.

Then we use `curl` to invoke the local endpoint with the test payload.

```sh
curl -v --header "Content-Type: application/json" --data @events/create-session.json http://127.0.0.1:7000/invoke
*   Trying 127.0.0.1:7000...
* Connected to 127.0.0.1 (127.0.0.1) port 7000
> POST /invoke HTTP/1.1
> Host: 127.0.0.1:7000
> User-Agent: curl/8.4.0
> Accept: */*
> Content-Type: application/json
> Content-Length: 1160
>
< HTTP/1.1 200 OK
< content-length: 247
<
* Connection #0 to host 127.0.0.1 left intact
{"statusCode":200,"isBase64Encoded":false,"body":"...","headers":{"Access-Control-Allow-Origin":"*","Content-Type":"application\/json; charset=utf-8","Access-Control-Allow-Headers":"*"}}
```

## Modifying the local server address

By default, the local Lambda server listens on `http://127.0.0.1:7000/invoke`.

Some testing tools, such as the [AWS Lambda runtime interface emulator](https://docs.aws.amazon.com/lambda/latest/dg/images-test.html), require a different endpoint. The port might already be in use, or you may want to bind a specific IP address. In these cases, use the following environment variables to control the local server:

- `LOCAL_LAMBDA_HOST` configures the local server to listen on a different TCP address.
- `LOCAL_LAMBDA_PORT` configures the local server to listen on a different TCP port.
- `LOCAL_LAMBDA_INVOCATION_ENDPOINT` forces the local server to listen on a different endpoint.

For example:

```sh
LOCAL_LAMBDA_PORT=8080 LOCAL_LAMBDA_INVOCATION_ENDPOINT=/2015-03-31/functions/function/invocations swift run
```

## See Also 

- <doc:Deployment>
