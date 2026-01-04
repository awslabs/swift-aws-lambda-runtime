# Lambda Managed Instances Example

This example demonstrates deploying Swift Lambda functions to Lambda Managed Instances using AWS SAM. Lambda Managed Instances provide serverless simplicity with EC2 flexibility and cost optimization by running your functions on customer-owned EC2 instances.

## Functions Included

1. **HelloJSON** - JSON input/output with structured data types
2. **Streaming** - Demonstrates response streaming capabilities
3. **BackgroundTasks** - Handles long-running background processing

## Prerequisites

- AWS CLI configured with appropriate permissions
- SAM CLI installed
- Swift 6.0+ installed
- An existing [Lambda Managed Instances capacity provider](https://docs.aws.amazon.com/lambda/latest/dg/lambda-managed-instances-capacity-providers.html)

## Capacity Provider Configuration

[Create your own capcity provider](https://docs.aws.amazon.com/lambda/latest/dg/lambda-managed-instances-capacity-providers.html#lambda-managed-instances-creating-capacity-provider) before deploying this example.

This example uses a pre-configured capacity provider with the ARN:
```
arn:aws:lambda:us-west-2:486652066693:capacity-provider:TestEC2
```

## Deployment

```bash
# Build the Swift packages
swift package archive --allow-network-access docker 

# Change the values below to match your setup 
REGION=us-west-2
CAPACITY_PROVIDER=arn:aws:lambda:us-west-2:486652066693:capacity-provider:TestEC2

# Deploy using SAM
sam deploy \
    --resolve-s3 \
    --template-file template.yaml \
    --stack-name swift-lambda-managed-instances \
    --capabilities CAPABILITY_IAM \
    --region ${REGION} \
    --parameter-overrides \
        CapacityProviderArn=${CAPACITY_PROVIDER}
```

## Function Details

### HelloJSON Function
- **Timeout**: 15 seconds (default)
- **Concurrency**: 8 per execution environment (default)
- **Input**: JSON `{"name": "string", "age": number}`
- **Output**: JSON `{"greetings": "string"}`

### Streaming Function
- **Timeout**: 60 seconds
- **Concurrency**: 8 per execution environment (default)
- **Features**: Response streaming enabled
- **Output**: Streams numbers with pauses

### BackgroundTasks Function
- **Timeout**: 300 seconds (5 minutes)
- **Concurrency**: 8 per execution environment (default)
- **Input**: JSON `{"message": "string"}`
- **Features**: Long-running background processing after response

## Testing with AWS CLI

After deployment, invoke each function with the AWS CLI:

### Test HelloJSON Function
```bash
REGION=us-west-2
aws lambda invoke \
--region ${REGION} \
--function-name swift-lambda-managed-instances-HelloJSON \
--payload $(echo '{ "name" : "Swift Developer", "age" : 50 }' | base64)  \
out.txt && cat out.txt && rm out.txt

# Expected output: {"greetings": "Hello Swift Developer. You look older than your age."}
```

### Test Streaming Function
```bash
# Get the Streaming URL
REGION=us-west-2
STREAMING_URL=$(aws cloudformation describe-stacks \
    --stack-name swift-lambda-managed-instances \
    --region ${REGION} \
    --query 'Stacks[0].Outputs[?OutputKey==`StreamingFunctionUrl`].OutputValue' \
    --output text)

# Set the AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, and AWS_SESSION_TOKEN environment variables
eval $(aws configure export-credentials --format env)

# Test with curl (streaming response)
curl "$STREAMING_URL" \
    --user "${AWS_ACCESS_KEY_ID}":"${AWS_SECRET_ACCESS_KEY}"   \
    --aws-sigv4 "aws:amz:${REGION}:lambda" \
    -H "x-amz-security-token: ${AWS_SESSION_TOKEN}" \
    --no-buffer

# Expected output: Numbers streaming with pauses
```

### Test BackgroundTasks Function
```bash
# Test with AWS CLI
REGION=us-west-2
aws lambda invoke \
--region ${REGION} \
--function-name swift-lambda-managed-instances-BackgroundTasks \
--payload $(echo '{ "message" : "Additional processing in the background" }' | base64)  \
out.txt && cat out.txt && rm out.txt

# Expected output: {"echoedMessage": "Additional processing in the background"}
# Note: Background processing continues after response is sent
```

## Cleanup

To remove all resources:
```bash
sam delete --stack-name swift-lambda-managed-instances --region ${REGION}$
```