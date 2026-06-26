# S3 Event Notifier

This example demonstrates how to write a Lambda that is invoked by an event originating from Amazon S3, such as a new object being uploaded to a bucket.

## Code

In this example the Lambda function receives an `S3Event` object defined in the `AWSLambdaEvents` library as input object. The `S3Event` object contains all the information about the S3 event that triggered the function, but what we are interested in is the bucket name and the object key, which are inside of a notification `Record`. The object contains an array of records, however since the Lambda function is triggered by a single event, we can safely assume that there is only one record in the array: the first one. Inside of this record, we can find the bucket name and the object key:

```swift
guard let s3NotificationRecord = event.records.first else {
    throw LambdaError.noNotificationRecord
}

let bucket = s3NotificationRecord.s3.bucket.name
let key = s3NotificationRecord.s3.object.key.replacingOccurrences(of: "+", with: " ")
```

The key is URL encoded, so we replace the `+` with a space.

## Build & Package 

To build & archive the package you can use the following commands:

```bash
swift build
swift package --allow-network-connections docker lambda-build
```

If there are no errors, a ZIP file should be ready to deploy, located at `.build/plugins/AWSLambdaBuilder/outputs/AWSLambdaBuilder/S3EventNotifier/S3EventNotifier.zip`.

## Deploy

> [!IMPORTANT]
> The Lambda function and the S3 bucket must be located in the same AWS Region. In the code below, we use `eu-west-1` (Ireland). 

To deploy the Lambda function, you can use the `lambda-deploy` plugin:

```bash
swift package --allow-network-connections all:443 lambda-deploy --region eu-west-1
```

This creates the Lambda function, provisions the necessary IAM role, and uploads the deployment package.

Besides deploying the Lambda function you also need to create the S3 bucket and configure it to send events to the Lambda function. You can do this using the following commands:

```bash
REGION=eu-west-1

aws s3api create-bucket     \
    --region "${REGION}"    \
    --bucket my-test-bucket \
    --create-bucket-configuration LocationConstraint="${REGION}"

aws lambda add-permission           \
    --region "${REGION}"            \
    --function-name S3EventNotifier \
    --statement-id S3InvokeFunction \
    --action lambda:InvokeFunction  \
    --principal s3.amazonaws.com    \
    --source-arn arn:aws:s3:::my-test-bucket

aws s3api put-bucket-notification-configuration \
    --region "${REGION}"    \
    --bucket my-test-bucket \
    --notification-configuration '{
        "LambdaFunctionConfigurations": [{
            "LambdaFunctionArn": "arn:aws:lambda:${REGION}:<YOUR_ACCOUNT_ID>:function:S3EventNotifier",
            "Events": ["s3:ObjectCreated:*"]
        }]
    }'

touch testfile.txt && aws s3 cp testfile.txt s3://my-test-bucket/
```

This will:
 - create a bucket named `my-test-bucket` in the `$REGION` region;
 - add a permission to the Lambda function to be invoked by Amazon S3;
 - configure the bucket to send `s3:ObjectCreated:*` events to the Lambda function named `S3EventNotifier`;
 - upload a file named `testfile.txt` to the bucket.

Replace `my-test-bucket` with your bucket name (bucket names are unique globaly and this one is already taken). Also replace `REGION` environment variable with the AWS Region where you deployed the Lambda function and `<YOUR_ACCOUNT_ID>` with your actual AWS account ID.

> [!IMPORTANT]
> The Lambda function and the S3 bucket must be located in the same AWS Region. Adjust the code above according to your closest AWS Region.

## ⚠️ Security and Reliability Notice

These are example applications for demonstration purposes. When deploying such infrastructure in production environments, we strongly encourage you to follow these best practices for improved security and resiliency:

- Enable access logging on API Gateway ([documentation](https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-logging.html))
- Ensure that AWS Lambda function is configured for function-level concurrent execution limit ([concurrency documentation](https://docs.aws.amazon.com/lambda/latest/dg/lambda-concurrency.html), [configuration guide](https://docs.aws.amazon.com/lambda/latest/dg/configuration-concurrency.html))
- Check encryption settings for Lambda environment variables ([documentation](https://docs.aws.amazon.com/lambda/latest/dg/configuration-envvars-encryption.html))
- Ensure that AWS Lambda function is configured for a Dead Letter Queue (DLQ) ([documentation](https://docs.aws.amazon.com/lambda/latest/dg/invocation-async-retain-records.html#invocation-dlq))
- Ensure that AWS Lambda function is configured inside a VPC when it needs to access private resources ([documentation](https://docs.aws.amazon.com/lambda/latest/dg/configuration-vpc.html), [code example](https://github.com/awslabs/swift-aws-lambda-runtime/tree/main/Examples/ServiceLifecycle%2BPostgres))