# A swift Service Lifecycle Lambda function with a managed PostgreSQL database

This example demonstrates a Swift Lambda function that uses Swift Service Lifecycle to manage a PostgreSQL connection. The function connects to an RDS PostgreSQL database in private subnets and queries user data.

## Architecture

- **Swift Lambda Function**: A network isolated Lambda function that Uses Swift ServiceLifecycle to manage PostgreSQL client lifecycle
- **PostgreSQL on Amazon RDS**: Database instance in private subnets with SSL/TLS encryption
- **HTTP API Gateway**: HTTP endpoint to invoke the Lambda function
- **VPC**: Custom VPC with private subnets only for complete network isolation
- **Security**: SSL/TLS connections with RDS root certificate verification, secure networking with security groups
- **Timeout Handling**: 3-second timeout mechanism to prevent database connection freeze
- **Secrets Manager**: Secure credential storage and management

For detailed infrastructure and cost information, see `INFRASTRUCTURE.md`.

## Implementation Details

The Lambda function demonstrates several key concepts:

1. **ServiceLifecycle Integration**: The PostgreSQL client and Lambda runtime are managed together using ServiceLifecycle, ensuring proper initialization and cleanup.

2. **SSL/TLS Security**: Connections to RDS use SSL/TLS with full certificate verification using region-specific RDS root certificates.

3. **Timeout Protection**: A custom timeout mechanism prevents the function from freezing when the database is unreachable (addresses PostgresNIO issue #489).

4. **Structured Response**: Returns a JSON array of `User` objects, making it suitable for API integration.

5. **Error Handling**: Comprehensive error handling for database connections, queries, and certificate loading.

6. **Task-local logger**: The application logger is bound once at startup with `withLogger(_:)`, so helper functions read `Logger.current` instead of receiving a logger parameter.

### Task-local logging across the service lifecycle

This example builds a single application `Logger` and binds it as the task-local `Logger.current` around the whole service group:

```swift
try await withLogger(self.logger) { _ in
    let lambdaRuntime = LambdaRuntime(logger: self.logger, body: self.handler)
    // ... build the prelude service ...
    let serviceGroup = ServiceGroup(
        services: [self.pgClient, preludeService],
        gracefulShutdownSignals: [.sigterm],
        cancellationSignals: [.sigint],
        logger: self.logger
    )
    try await serviceGroup.run()
}
```

ServiceLifecycle propagates the task-local through the `ServiceGroup` and into every task it spawns. Helper functions can then log with the bound logger without it being threaded through their signatures:

```swift
private func prepareDatabase() async throws {
    Logger.current.trace("Testing if table exists")  // no logger parameter
    // ...
}
```

> **Notes**
> - The bootstrap binding (`withLogger(self.logger) { ... }`) works on any supported toolchain. The Lambda runtime re-binding the **per-invocation** logger (with request/trace IDs) requires **Swift 6.2 or later**.
> - `ServiceGroup` and `PostgresClient` still take an explicit `logger:` — those are external APIs and are configured directly, not via the task-local.

## Prerequisites

- Swift 6.x toolchain
- Docker (for building Lambda functions)
- AWS CLI configured with appropriate permissions
- SAM CLI installed

## Database Schema

In the context of this demo, the Lambda function creates the table and populates it with data at first run.

The Lambda function expects a `users` table with the following structure and returns results as `User` objects:

```sql
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) NOT NULL
);

-- Insert some sample data
INSERT INTO users (username) VALUES ('alice'), ('bob'), ('charlie');
```

The Swift `User` model:
```swift
struct User: Codable {
    let id: Int
    let username: String
}
```

## Environment Variables

The Lambda function uses the following environment variables for database connection:
- `DB_HOST`: Database hostname (set by CloudFormation from RDS endpoint)
- `DB_USER`: Database username (retrieved from Secrets Manager)
- `DB_PASSWORD`: Database password (retrieved from Secrets Manager)
- `DB_NAME`: Database name (defaults to "test")
- `AWS_REGION`: AWS region for selecting the correct RDS root certificate

## Deployment

### Option 1: Using the deployment script

```bash
./deploy.sh
```

### Option 2: Manual deployment

1. **Build the Lambda function:**
   ```bash
   swift package --allow-network-connections docker lambda-build
   ```

2. **Deploy with SAM:**
   ```bash
   sam deploy
   ```

## Getting Connection Details

After deployment, get the database and API Gateway connection details:

```bash
aws cloudformation describe-stacks \
  --stack-name servicelifecycle-stack \
  --query 'Stacks[0].Outputs'
```

The output will include:
- **DatabaseEndpoint**: Hostname to connect to
- **DatabasePort**: Port number (5432)
- **DatabaseName**: Database name
- **DatabaseUsername**: Username
- **DatabasePassword**: Password
- **DatabaseConnectionString**: Complete connection string

## Connecting to the Database

The database is deployed in **private subnets** and is **not directly accessible** from the internet. This follows AWS security best practices.

To connect to the database, you would need to create an Amazon EC2 instance in a public subnet (which you'd need to add to the VPC) or use AWS Systems Manager Session Manager for secure access to an EC2 instance in a private subnet. The current template uses a private-only architecture for maximum security.

You can access the database connection details in the output of the SAM template:

```bash
# Get the connection details from CloudFormation outputs
DB_HOST=$(aws cloudformation describe-stacks --stack-name servicelifecycle-stack --query 'Stacks[0].Outputs[?OutputKey==`DatabaseEndpoint`].OutputValue' --output text)
DB_PORT=$(aws cloudformation describe-stacks --stack-name servicelifecycle-stack --query 'Stacks[0].Outputs[?OutputKey==`DatabasePort`].OutputValue' --output text)
DB_NAME=$(aws cloudformation describe-stacks --stack-name servicelifecycle-stack --query 'Stacks[0].Outputs[?OutputKey==`DatabaseName`].OutputValue' --output text)

# Get the database password from Secrets Manager
SECRET_ARN=$(aws cloudformation describe-stacks --stack-name servicelifecycle-stack --query 'Stacks[0].Outputs[?OutputKey==`DatabaseSecretArn`].OutputValue' --output text)
DB_USERNAME=$(aws secretsmanager get-secret-value --secret-id "$SECRET_ARN" --query 'SecretString' --output text | jq -r '.username')
DB_PASSWORD=$(aws secretsmanager get-secret-value --secret-id "$SECRET_ARN" --query 'SecretString' --output text | jq -r '.password')

# Connect with psql on Amazon EC2
psql -h "$DB_HOST:$DB_PORT" -U "$DB_USER" -d "$DB_NAME"
```

## Testing the Lambda Function

Get the API Gateway endpoint and test the function:

```bash
# Get the API endpoint
API_ENDPOINT=$(aws cloudformation describe-stacks --stack-name servicelifecycle-stack --query 'Stacks[0].Outputs[?OutputKey==`APIGatewayEndpoint`].OutputValue' --output text)

# Test the function
curl "$API_ENDPOINT"
```

The function will:
1. Connect to the PostgreSQL database using SSL/TLS with RDS root certificate verification
2. Query the `users` table with a 3-second timeout to prevent freezing
3. Log the results for each user found
4. Return a JSON array of `User` objects with `id` and `username` fields

Example response:
```json
[
  {"id": 1, "username": "alice"},
  {"id": 2, "username": "bob"},
  {"id": 3, "username": "charlie"}
]
```

## Monitoring

Check the Lambda function logs:

```bash
sam logs -n ServiceLifecycleLambda --stack-name servicelifecycle-stack --tail
```

## Security Considerations

✅ **Security Best Practices Implemented**:

This example follows AWS security best practices:

1. **Private Database**: Database is deployed in private subnets with no internet access
2. **Complete Network Isolation**: Private subnets only with no internet connectivity
3. **Security Groups**: Restrictive security groups following least privilege principle
4. **Secrets Management**: Database credentials stored in AWS Secrets Manager
5. **Encryption**: SSL/TLS for database connections with certificate verification
6. **Minimal Attack Surface**: No public subnets or internet gateways

The infrastructure implements secure networking patterns suitable for production workloads.

## Cost Optimization

The template is optimized for cost:
- `db.t3.micro` instance (eligible for free tier)
- Minimal storage allocation (20GB)
- No Multi-AZ deployment
- No automated backups
- No NAT Gateway or Internet Gateway
- Private-only architecture

**Estimated cost: ~$16.62/month (or ~$0.45/month with RDS Free Tier)**

For detailed cost breakdown, see `INFRASTRUCTURE.md`.

## Cleanup

To delete all resources:

```bash
sam delete --stack-name servicelifecycle-stack
```

## SSL Certificate Support

This example includes RDS root certificates for secure SSL/TLS connections. Currently supported regions:
- `us-east-1`: US East (N. Virginia)
- `eu-central-1`: Europe (Frankfurt)

To add support for additional regions:
1. Download the appropriate root certificate from [AWS RDS SSL documentation](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.SSL.html)
2. Create a new Swift file in `Sources/RDSCertificates/` with the certificate PEM data
3. Add the region mapping to `rootRDSCertificates` dictionary in `RootRDSCert.swift`

## Troubleshooting

when deploying with SAM and the `template.yaml` file included in this example, there shouldn't be any error. However, when you try to create such infarstructure on your own or using different infrastructure as code (IaC) tools, it's likely to iterate before getting everything configured. We compiled a couple of the most common configuration errors and their solution:

### Lambda can't connect to database

1. Check security groups allow traffic on port 5432 between Lambda and RDS security groups
2. Verify both Lambda and RDS are deployed in the same private subnets
3. Verify database credentials are correctly retrieved from Secrets Manager and that the Lambda execution policies have permissions to read the secret
4. Ensure the RDS instance is running and healthy

### Database connection timeout

The PostgreSQL client may freeze if the database is unreachable. This example implements a 3-second timeout mechanism to prevent this issue. If the connection or query takes longer than 3 seconds, the function will timeout and return an empty array. Ensure:
1. Database is running and accessible
2. Security groups are properly configured
3. Network connectivity is available
4. SSL certificates are properly configured for your AWS region

### Build failures

Ensure you have:
1. Swift 6.x toolchain installed
2. Docker running
3. Proper network connectivity for downloading dependencies
4. All required dependencies: PostgresNIO, AWSLambdaRuntime, and ServiceLifecycle

## Files

- `template.yaml`: SAM template defining all AWS resources
- `INFRASTRUCTURE.md`: Detailed infrastructure architecture documentation
- `samconfig.toml`: SAM configuration file
- `deploy.sh`: Deployment script
- `Sources/Lambda.swift`: Swift Lambda function code with ServiceLifecycle integration
- `Sources/Timeout.swift`: Timeout utility to prevent database connection freezes
- `Sources/RDSCertificates/RootRDSCert.swift`: RDS root certificate management
- `Sources/RDSCertificates/us-east-1.swift`: US East 1 region root certificate
- `Sources/RDSCertificates/eu-central-1.swift`: EU Central 1 region root certificate
- `Package.swift`: Swift package definition with PostgresNIO, AWSLambdaRuntime, and ServiceLifecycle dependencies

## ⚠️ Security and Reliability Notice

These are example applications for demonstration purposes. When deploying such infrastructure in production environments, we strongly encourage you to follow these best practices for improved security and resiliency:

- Enable access logging on API Gateway ([documentation](https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-logging.html))
- Ensure that AWS Lambda function is configured for function-level concurrent execution limit ([concurrency documentation](https://docs.aws.amazon.com/lambda/latest/dg/lambda-concurrency.html), [configuration guide](https://docs.aws.amazon.com/lambda/latest/dg/configuration-concurrency.html))
- Check encryption settings for Lambda environment variables ([documentation](https://docs.aws.amazon.com/lambda/latest/dg/configuration-envvars-encryption.html))
- Ensure that AWS Lambda function is configured for a Dead Letter Queue (DLQ) ([documentation](https://docs.aws.amazon.com/lambda/latest/dg/invocation-async-retain-records.html#invocation-dlq))
- Ensure that AWS Lambda function is configured inside a VPC when it needs to access private resources ([documentation](https://docs.aws.amazon.com/lambda/latest/dg/configuration-vpc.html), [code example](https://github.com/awslabs/swift-aws-lambda-runtime/tree/main/Examples/ServiceLifecycle%2BPostgres))