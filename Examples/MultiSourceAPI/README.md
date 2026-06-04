# Multi-Source API Example

This example demonstrates a Lambda function that handles requests from both Application Load Balancer (ALB) and API Gateway V2 by accepting a raw `ByteBuffer` and decoding the appropriate event type.

## Overview

The Lambda handler receives events as `ByteBuffer` and attempts to decode them as either:
- `ALBTargetGroupRequest` - for requests from Application Load Balancer
- `APIGatewayV2Request` - for requests from API Gateway V2

Based on the successfully decoded type, it returns an appropriate response.

## Building

```bash
swift package --allow-network-connections docker lambda-build
```

## Deploying

Deploy using SAM:

```bash
sam deploy \
  --resolve-s3 \
  --template-file template.yaml \
  --stack-name MultiSourceAPI \
  --capabilities CAPABILITY_IAM
```

## Testing

After deployment, SAM will output two URLs:

### Test API Gateway V2:
```bash
curl https://<api-id>.execute-api.<region>.amazonaws.com/apigw/test
```

Expected response:
```json
{"source":"APIGatewayV2","path":"/apigw/test"}
```

### Test ALB:
```bash
curl http://<alb-dns-name>/alb/test
```

Expected response:
```json
{"source":"ALB","path":"/alb/test"}
```

## How It Works

The handler uses Swift's type-safe decoding to determine the event source:

1. Receives raw `ByteBuffer` event
2. Attempts to decode as `ALBTargetGroupRequest`
3. If that fails, attempts to decode as `APIGatewayV2Request`
4. Returns appropriate response based on the decoded type
5. Throws error if neither decoding succeeds

This pattern is useful when a single Lambda function needs to handle requests from multiple sources.
