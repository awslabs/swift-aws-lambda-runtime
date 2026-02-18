# Multi-Tenant Lambda Function Example

This example demonstrates how to build a multi-tenant Lambda function using Swift and AWS Lambda's tenant isolation mode. Tenant isolation ensures that execution environments are dedicated to specific tenants, providing strict isolation for processing tenant-specific code or data.

## Overview

This example implements a request tracking system that maintains separate counters and request histories for each tenant. The Lambda function:

- Accepts requests from multiple tenants via API Gateway (MultiTenant)
- Accepts direct JSON payloads without API Gateway (MultiTenantLocal)
- Maintains isolated execution environments per tenant
- Tracks request counts and timestamps for each tenant
- Returns tenant-specific data in JSON format

## What is Tenant Isolation Mode?

AWS Lambda's tenant isolation mode routes requests to execution environments based on a customer-specified tenant identifier. This ensures that:

- **Execution environments are never reused across different tenants** - Each tenant gets dedicated execution environments
- **Data isolation** - Tenant-specific data remains isolated from other tenants
- **Firecracker virtualization** - Provides workload isolation at the infrastructure level

### When to Use Tenant Isolation

Use tenant isolation mode when building multi-tenant applications that:

- **Execute end-user supplied code** - Limits the impact of potentially incorrect or malicious user code
- **Process tenant-specific data** - Prevents exposure of sensitive data to other tenants
- **Require strict isolation guarantees** - Such as SaaS platforms for workflow automation or code execution

## Architecture

The example consists of:

1. **TenantData** - Immutable struct tracking tenant information:
   - `tenantID`: Unique identifier for the tenant
   - `requestCount`: Total number of requests from this tenant
   - `firstRequest`: Unix timestamp (seconds since epoch) of the first request
   - `requests`: Array of individual request records

2. **TenantDataStore** - Actor-based storage providing thread-safe access to tenant data across invocations

3. **Lambda Handler** - Processes API Gateway requests and manages tenant data

4. **MultiTenantLocal Handler** - Processes plain JSON requests without API Gateway

## Code Structure

```swift
// Immutable tenant data structure
struct TenantData: Codable {
    let tenantID: String
    let requestCount: Int
    let firstRequest: String
    let requests: [TenantRequest]
    
    func addingRequest() -> TenantData {
        // Returns new instance with incremented count
    }
}

// Thread-safe tenant storage using Swift actors
actor TenantDataStore {
    private var tenants: [String: TenantData] = [:]
    
    subscript(id: String) -> TenantData? {
        tenants[id]
    }
    
    func update(id: String, data: TenantData) {
        tenants[id] = data
    }
}

// Lambda handler extracts tenant ID from context
let runtime = LambdaRuntime {
    (event: APIGatewayRequest, context: LambdaContext) -> APIGatewayResponse in
    
    guard let tenantID = context.tenantID else {
        return APIGatewayResponse(statusCode: .badRequest, body: "No Tenant ID provided")
    }
    
    // Process request for this tenant
    let currentData = await tenants[tenantID] ?? TenantData(tenantID: tenantID)
    let updatedData = currentData.addingRequest()
    await tenants.update(id: tenantID, data: updatedData)
    
    return try APIGatewayResponse(statusCode: .ok, encodableBody: updatedData)
}
```

## Configuration

### SAM Template (template.yaml)

The function is configured with tenant isolation mode and API Gateway parameter mapping in the SAM template:

```yaml
# API Gateway REST API with parameter mapping
MultiTenantApi:
  Type: AWS::Serverless::Api
  Properties:
    StageName: Prod
    DefinitionBody:
      openapi: 3.0.1
      paths:
        /:
          get:
            parameters:
              - name: tenant-id
                in: query
                required: true
            x-amazon-apigateway-integration:
              type: aws_proxy
              httpMethod: POST
              uri: !Sub arn:aws:apigateway:${AWS::Region}:lambda:path/2015-03-31/functions/${MultiTenantLambda.Arn}/invocations
              # Map query parameter to Lambda tenant header
              requestParameters:
                integration.request.header.X-Amz-Tenant-Id: method.request.querystring.tenant-id

# Lambda function with tenant isolation
MultiTenantLambda:
  Type: AWS::Serverless::Function
  Properties:
    Runtime: provided.al2023
    Architectures:
      - arm64
    # Enable tenant isolation mode
    TenancyConfig:
      TenantIsolationMode: PER_TENANT
```

### Key Configuration Points

- **TenancyConfig.TenantIsolationMode**: Set to `PER_TENANT` to enable tenant isolation
- **Parameter Mapping**: API Gateway maps the `tenant-id` query parameter to the `X-Amz-Tenant-Id` header required by Lambda
- **REST API**: Uses REST API (not HTTP API) to support request parameter mapping
- **OpenAPI Definition**: Defines the integration using OpenAPI 3.0 specification for fine-grained control
- **Immutable property**: Tenant isolation can only be enabled when creating a new function
- **Required tenant-id**: All invocations must include a tenant identifier

### Why Parameter Mapping is Required

Lambda's tenant isolation feature requires the tenant ID to be passed via the `X-Amz-Tenant-Id` header. When using API Gateway:

1. **Client sends request** with `tenant-id` as a query parameter
2. **API Gateway transforms** the query parameter into the `X-Amz-Tenant-Id` header
3. **Lambda receives** the header and routes to the appropriate tenant-isolated environment

This mapping is configured in the `x-amazon-apigateway-integration` section using:
```yaml
requestParameters:
  integration.request.header.X-Amz-Tenant-Id: method.request.querystring.tenant-id
```

## Deployment

### Prerequisites

- Swift (>=6.2)
- Docker (for cross-compilation to Amazon Linux)
- AWS SAM CLI (>=1.147.1)
- AWS CLI configured with appropriate credentials

### Build and Deploy

1. **Build the Lambda function**:
   ```bash
   swift package archive --allow-network-connections docker
   ```

2. **Deploy using SAM**:
   ```bash
   sam deploy --guided
   ```

3. **Note the API Gateway endpoint** from the CloudFormation outputs

## Testing

### Local Testing (No API Gateway)

Run the simple handler locally and invoke it directly using the local server. This example does not depend on API Gateway or its request/response types.

1. Start the local server:
   ```bash
   swift run MultiTenantLocal
   ```

2. Invoke with a tenant header and a JSON body:
   ```bash
   # Test multi-tenant function locally
   curl -X POST http://127.0.0.1:7000/invoke \
     -H "Content-Type: application/json" \
     -H "Lambda-Runtime-Aws-Tenant-Id: tenant-123" \
     -d '{"message" :  "hello"}'
   ```

### Using API Gateway

The tenant ID is passed as a query parameter. API Gateway automatically maps it to the `X-Amz-Tenant-Id` header:

```bash
# Request from tenant "alice"
curl "https://your-api-id.execute-api.us-east-1.amazonaws.com/Prod?tenant-id=alice"

# Request from tenant "bob"  
curl "https://your-api-id.execute-api.us-east-1.amazonaws.com/Prod?tenant-id=bob"

# Multiple requests from the same tenant will reuse the execution environment
for i in {1..5}; do
  curl "https://your-api-id.execute-api.us-east-1.amazonaws.com/Prod?tenant-id=alice"
done
```

### Using AWS CLI (Direct Lambda Invocation)

For direct Lambda invocation without API Gateway:

```bash
# Synchronous invocation
aws lambda invoke \
    --function-name MultiTenantLambda \
    --tenant-id alice \
    response.json

# View the response
cat response.json
```

### Expected Response

```json
{
  "tenantID": "alice",
  "requestCount": 3,
  "firstRequest": "1705320000.123456",
  "requests": [
    {
      "requestNumber": 1,
      "timestamp": "1705320000.123456"
    },
    {
      "requestNumber": 2,
      "timestamp": "1705320075.789012"
    },
    {
      "requestNumber": 3,
      "timestamp": "1705320150.345678"
    }
  ]
}
```

**Note**: Timestamps are Unix epoch times (seconds since January 1, 1970) for cross-platform compatibility.

## How Tenant Isolation Works

1. **Request arrives** with a tenant identifier (via query parameter, header, or direct invocation)
2. **Lambda routes the request** to an execution environment dedicated to that tenant
3. **Environment reuse** - Subsequent requests from the same tenant reuse the same environment (warm start)
4. **Isolation guarantee** - Execution environments are never shared between different tenants
5. **Data persistence** - Tenant data persists in memory across invocations within the same execution environment

## Important Considerations

### Concurrency and Scaling

- Lambda imposes a limit of **2,500 tenant-isolated execution environments** (active or idle) for every 1,000 concurrent executions
- Each tenant can scale independently based on their request volume
- Cold starts occur more frequently due to tenant-specific environments

### Pricing

- Standard Lambda pricing applies (compute time and requests)
- **Additional charge** when Lambda creates a new tenant-isolated execution environment
- Price depends on allocated memory and CPU architecture
- See [AWS Lambda Pricing](https://aws.amazon.com/lambda/pricing) for details

### Limitations

Tenant isolation mode is **not supported** with:
- Function URLs
- Provisioned concurrency
- SnapStart

### Supported Invocation Methods

- ✅ Synchronous invocations
- ✅ Asynchronous invocations
- ✅ API Gateway event triggers
- ✅ AWS SDK invocations

## Security Best Practices

1. **Execution role applies to all tenants** - Use IAM policies to restrict access to tenant-specific resources
2. **Validate tenant identifiers** - Ensure tenant IDs are properly authenticated and authorized
3. **Implement tenant-aware logging** - Include tenant ID in CloudWatch logs for audit trails
4. **Set appropriate timeouts** - Configure function timeout based on expected workload
5. **Monitor per-tenant metrics** - Use CloudWatch to track invocations, errors, and duration per tenant

## Monitoring

### CloudWatch Metrics

Lambda automatically publishes metrics with tenant dimensions:

- `Invocations` - Number of invocations per tenant
- `Duration` - Execution time per tenant
- `Errors` - Error count per tenant
- `Throttles` - Throttled requests per tenant

### Accessing Metrics

```bash
# Get invocation count for a specific tenant
aws cloudwatch get-metric-statistics \
    --namespace AWS/Lambda \
    --metric-name Invocations \
    --dimensions Name=FunctionName,Value=MultiTenant Name=TenantId,Value=alice \
    --start-time 2024-01-15T00:00:00Z \
    --end-time 2024-01-15T23:59:59Z \
    --period 3600 \
    --statistics Sum
```

## Learn More

- [AWS Lambda Tenant Isolation Documentation](https://docs.aws.amazon.com/lambda/latest/dg/tenant-isolation.html)
- [Configuring Tenant Isolation](https://docs.aws.amazon.com/lambda/latest/dg/tenant-isolation-configure.html)
- [Invoking Tenant-Isolated Functions](https://docs.aws.amazon.com/lambda/latest/dg/tenant-isolation-invoke.html)
- [AWS Blog: Streamlined Multi-Tenant Application Development](https://aws.amazon.com/blogs/aws/streamlined-multi-tenant-application-development-with-tenant-isolation-mode-in-aws-lambda/)
- [Swift AWS Lambda Runtime](https://github.com/swift-server/swift-aws-lambda-runtime)

## License

This example is part of the Swift AWS Lambda Runtime project and is licensed under Apache License 2.0.
