# AWS Lambda Startup Time Measurement Scripts

A set of simple bash scripts to measure AWS Lambda cold start and warm start times. These scripts deploy a Lambda function, invoke it multiple times, retrieve execution metrics from CloudWatch Logs (the authoritative source), and output statistical results.

## Overview

This toolkit provides two measurement scripts:

- **measure-cold-start.sh** - Measures cold start times by forcing a new execution environment between invocations
- **measure-warm-start.sh** - Measures warm start times by reusing the same execution environment

Both scripts follow the KISS (Keep It Simple, Stupid) principle with minimal dependencies and straightforward implementations.

**Note:** Lambda functions are deployed with arm64 architecture by default.

## Purpose

Understanding Lambda startup performance is critical for optimizing serverless applications. These scripts help you:

- Measure cold start initialization times when Lambda creates a new execution environment
- Measure warm start execution times when Lambda reuses an existing environment
- Gather statistically valid datasets through multiple iterations
- Compare performance across different runtimes, configurations, or code changes

## Dependencies

The following tools must be installed and available in your PATH:

- **AWS CLI v2** - For Lambda and CloudWatch Logs operations
  - Installation: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
  - Must be configured with valid credentials (`aws configure`)

- **jq** - For JSON parsing
  - Installation: `brew install jq` (macOS) or `apt-get install jq` (Linux)

- **bc** - For floating-point arithmetic in statistics calculations
  - Usually pre-installed on most systems
  - Installation: `brew install bc` (macOS) or `apt-get install bc` (Linux)

- **grep** with Perl regex support - For log parsing
  - Usually pre-installed on most systems

## Prerequisites

Before running the scripts, ensure you have:

1. **AWS Credentials** - Configured via `aws configure` or environment variables
2. **IAM Role** - An IAM role with Lambda execution permissions (ARN required)
3. **Lambda Deployment Package** - A ZIP file containing your Lambda function code
4. **Permissions** - Your AWS credentials must have permissions to:
   - Create/update Lambda functions
   - Invoke Lambda functions
   - Read CloudWatch Logs

## Command-Line Parameters

### Required Parameters

Both scripts require these parameters:

| Parameter | Description | Example |
|-----------|-------------|---------|
| `--zip-file <path>` | Path to Lambda deployment package (ZIP file) | `--zip-file ./my-function.zip` |
| `--role-arn <arn>` | IAM role ARN for Lambda execution | `--role-arn arn:aws:iam::123456789012:role/lambda-role` |

### Optional Parameters

| Parameter | Description | Default Value |
|-----------|-------------|---------------|
| `--runtime <runtime>` | Lambda runtime environment | `provided.al2023` |
| `--iterations <n>` | Number of measurements to collect | `10` |
| `--event-file <path>` | Path to JSON event payload file | Simple string: "Performance test" |
| `--function-name <name>` | Lambda function name | `lambda-perf-test` |
| `--handler <handler>` | Lambda handler | `bootstrap` |

### Default Values

- **Runtime**: `provided.al2023` - AWS Lambda custom runtime
- **Iterations**: `10` - Provides a reasonable sample size for statistical analysis
- **Function Name**: `lambda-perf-test` - Automatically generated name
- **Handler**: `bootstrap` - Default for custom runtimes
- **Event Payload**: `"Performance test"` - Simple string payload

## Usage Examples

### Basic Cold Start Measurement

Measure cold start times with default settings (10 iterations):

```bash
./measure-cold-start.sh \
    --zip-file ./my-function.zip \
    --role-arn arn:aws:iam::123456789012:role/lambda-role
```

### Cold Start with Custom Configuration

Measure cold start times with custom runtime and more iterations:

```bash
./measure-cold-start.sh \
    --zip-file ./my-function.zip \
    --role-arn arn:aws:iam::123456789012:role/lambda-role \
    --runtime provided.al2023 \
    --iterations 15 \
    --function-name my-perf-test
```

### Cold Start with Custom Event Payload

Use a JSON file for the invocation payload:

```bash
./measure-cold-start.sh \
    --zip-file ./my-function.zip \
    --role-arn arn:aws:iam::123456789012:role/lambda-role \
    --event-file ./example-event.json \
    --iterations 20
```

### Basic Warm Start Measurement

Measure warm start times with default settings:

```bash
./measure-warm-start.sh \
    --zip-file ./my-function.zip \
    --role-arn arn:aws:iam::123456789012:role/lambda-role
```

### Warm Start with Custom Configuration

Measure warm start times with more iterations:

```bash
./measure-warm-start.sh \
    --zip-file ./my-function.zip \
    --role-arn arn:aws:iam::123456789012:role/lambda-role \
    --runtime provided.al2023 \
    --iterations 25 \
    --event-file ./custom-event.json
```

### Comparing Cold vs Warm Starts

Run both scripts with the same configuration to compare:

```bash
# Measure cold starts
./measure-cold-start.sh \
    --zip-file ./my-function.zip \
    --role-arn arn:aws:iam::123456789012:role/lambda-role \
    --iterations 10

# Measure warm starts
./measure-warm-start.sh \
    --zip-file ./my-function.zip \
    --role-arn arn:aws:iam::123456789012:role/lambda-role \
    --iterations 10
```

## Example Output

### Cold Start Measurement Output

```
=== Cold Start Measurement Configuration ===
Function Name: lambda-perf-test
ZIP File: ./my-function.zip
Runtime: provided.al2023
Handler: bootstrap
Iterations: 10
Role ARN: arn:aws:iam::123456789012:role/lambda-role

Deploying function: lambda-perf-test
Function exists, updating code...
Waiting for function to be active...
Function deployed successfully

=== Starting Cold Start Measurements ===
Iteration 1/10
  Request ID: abc-123-def-456
  Duration: 245.67ms
  Forcing cold start...

Iteration 2/10
  Request ID: ghi-789-jkl-012
  Duration: 198.34ms
  Forcing cold start...

Iteration 3/10
  Request ID: mno-345-pqr-678
  Duration: 223.45ms
  Forcing cold start...

...

=== Cold Start Measurement Results ===
Individual measurements:
  Measurement 1: 245.67ms
  Measurement 2: 198.34ms
  Measurement 3: 223.45ms
  Measurement 4: 267.89ms
  Measurement 5: 201.23ms
  Measurement 6: 234.56ms
  Measurement 7: 189.12ms
  Measurement 8: 256.78ms
  Measurement 9: 212.34ms
  Measurement 10: 225.67ms

=== Statistics ===
  Count: 10
  Average: 225.51ms
  Min: 189.12ms
  Max: 267.89ms
```

### Warm Start Measurement Output

```
=== Warm Start Measurement Configuration ===
Function Name: lambda-perf-test
ZIP File: ./my-function.zip
Runtime: provided.al2023
Handler: bootstrap
Iterations: 10
Role ARN: arn:aws:iam::123456789012:role/lambda-role

Deploying function: lambda-perf-test
Function exists, updating code...
Waiting for function to be active...
Function deployed successfully

=== Starting Warm Start Measurements ===
Iteration 1/10
  Request ID: stu-901-vwx-234
  Duration: 12.45ms

Iteration 2/10
  Request ID: yza-567-bcd-890
  Duration: 8.23ms

Iteration 3/10
  Request ID: efg-123-hij-456
  Duration: 9.67ms

...

=== Warm Start Measurement Results ===
Individual measurements:
  Measurement 1: 12.45ms
  Measurement 2: 8.23ms
  Measurement 3: 9.67ms
  Measurement 4: 11.34ms
  Measurement 5: 7.89ms
  Measurement 6: 10.12ms
  Measurement 7: 8.56ms
  Measurement 8: 9.23ms
  Measurement 9: 10.78ms
  Measurement 10: 8.91ms

=== Statistics ===
  Count: 10
  Average: 9.72ms
  Min: 7.89ms
  Max: 12.45ms
```

## How It Works

### Cold Start Measurement Process

1. **Deploy Function** - Creates or updates the Lambda function with your ZIP file (using arm64 architecture)
2. **Invoke Function** - Calls the Lambda function via AWS CLI
3. **Capture Invocation ID** - Extracts the request ID from the invocation response
4. **Retrieve Metrics** - Queries CloudWatch Logs using the invocation ID
5. **Parse Duration** - Extracts the duration from the REPORT log line
6. **Force Cold Start** - Updates an environment variable to force a new execution environment
7. **Repeat** - Continues for the specified number of iterations
8. **Calculate Statistics** - Computes average, min, and max from all measurements

### Warm Start Measurement Process

1. **Deploy Function** - Creates or updates the Lambda function with your ZIP file (using arm64 architecture)
2. **Invoke Function** - Calls the Lambda function via AWS CLI
3. **Capture Invocation ID** - Extracts the request ID from the invocation response
4. **Retrieve Metrics** - Queries CloudWatch Logs using the invocation ID
5. **Parse Duration** - Extracts the duration from the REPORT log line
6. **Repeat** - Continues for the specified number of iterations (without forcing cold starts)
7. **Calculate Statistics** - Computes average, min, and max from all measurements

### CloudWatch Logs as Source of Truth

The scripts use CloudWatch Logs as the authoritative source for execution times because:

- CloudWatch Logs contain the official AWS-recorded execution duration
- The REPORT log line includes precise timing information
- Invocation IDs ensure correct correlation between invocations and log entries
- This approach is more reliable than client-side timing

### Cold Start Forcing Mechanism

The cold start script forces new execution environments by:

1. Updating the Lambda function's environment variables with a timestamp
2. Waiting for the configuration update to complete
3. Adding a 2-second delay to ensure the environment is recycled
4. The next invocation will use a fresh execution environment (cold start)

## Performance Expectations

### Typical Execution Times

- **Cold Start Measurement** (10 iterations): ~60-100 seconds
  - Each iteration: ~6-10 seconds (invocation + log retrieval + cold start forcing)

- **Warm Start Measurement** (10 iterations): ~30-50 seconds
  - Each iteration: ~3-5 seconds (invocation + log retrieval)

### CloudWatch Logs Latency

- Logs typically appear in CloudWatch within 1-3 seconds
- The scripts implement retry logic (up to 10 attempts with 1-second delays)
- Initial 2-second wait before querying logs

## Event Payload

### Using the Default Payload

If no `--event-file` is specified, the scripts use a simple string payload: `"Performance test"`

### Using a Custom Event File

Create a JSON file with your desired payload structure:

```json
{
  "message": "Hello World",
  "timestamp": "2024-01-01T00:00:00Z",
  "userId": "user-123",
  "data": {
    "key": "value"
  }
}
```

Then reference it with `--event-file`:

```bash
./measure-cold-start.sh \
    --zip-file ./my-function.zip \
    --role-arn arn:aws:iam::123456789012:role/lambda-role \
    --event-file ./my-event.json
```

### Example Event File

An `example-event.json` file is provided as a template:

```json
{
  "_comment": "Example event payload for Lambda function invocation",
  "_usage": "Use this file with --event-file parameter or modify for your specific Lambda function",
  "message": "Hello World",
  "timestamp": "2024-01-01T00:00:00Z"
}
```

## File Structure

```
lambda-measurement/
├── measure-cold-start.sh      # Cold start measurement script
├── measure-warm-start.sh      # Warm start measurement script
├── shared-utils.sh            # Shared utility functions
├── example-event.json         # Example event payload
├── README.md                  # This documentation
└── test/                      # Test directory (optional)
    ├── test_statistics.bats   # Unit tests
    └── test_properties.py     # Property-based tests
```

## Troubleshooting

### AWS CLI Not Found

**Error**: `ERROR: AWS CLI is not installed or not in PATH`

**Solution**: Install AWS CLI v2 from https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html

### Missing Dependencies

**Error**: `ERROR: jq is not installed or not in PATH` or `ERROR: bc is not installed or not in PATH`

**Solution**: Install the missing tool:
- macOS: `brew install jq bc`
- Linux: `apt-get install jq bc` or `yum install jq bc`

### ZIP File Not Found

**Error**: `ERROR: ZIP file not found: ./my-function.zip`

**Solution**: Verify the path to your ZIP file is correct and the file exists

### IAM Role Permissions

**Error**: Function deployment fails with permission errors

**Solution**: Ensure your IAM role has the following permissions:
- `lambda:CreateFunction`
- `lambda:UpdateFunctionCode`
- `lambda:UpdateFunctionConfiguration`
- `lambda:InvokeFunction`
- `lambda:GetFunction`
- `logs:FilterLogEvents`

### CloudWatch Logs Not Available

**Error**: `ERROR: Could not retrieve logs for request <id>`

**Solution**: 
- Logs may take longer than expected to appear
- Check that your Lambda function has CloudWatch Logs permissions
- Verify the log group `/aws/lambda/<function-name>` exists
- Increase the retry attempts in `get_duration_from_logs()` if needed

### Failed Invocations

**Warning**: `WARNING: Failed to get duration for iteration N, skipping`

**Solution**: 
- Check Lambda function logs for errors
- Verify your function code is working correctly
- Ensure the event payload is compatible with your function

## Best Practices

1. **Run Multiple Iterations** - Use at least 10 iterations for statistically valid results
2. **Consistent Configuration** - Use the same parameters when comparing measurements
3. **Warm Up First** - For warm start measurements, the first invocation may be slower
4. **Clean Environment** - Delete test functions after measurements to avoid costs
5. **Monitor Costs** - Lambda invocations and CloudWatch Logs queries incur AWS charges
6. **Test Realistic Payloads** - Use event payloads that match your production workload

## Limitations

- **Minimal Error Handling** - Scripts follow the KISS principle with basic error handling
- **Sequential Execution** - Measurements are performed sequentially, not in parallel
- **CloudWatch Latency** - Log retrieval adds 2-3 seconds per measurement
- **Environment Variable Limit** - Cold start forcing via environment variables has AWS limits
- **No Concurrent Invocations** - Scripts don't test concurrent execution scenarios

## Contributing

These scripts are designed to be simple and easy to modify. Feel free to:

- Adjust retry logic in `get_duration_from_logs()`
- Modify default values in `parse_arguments()`
- Add additional statistics calculations
- Implement alternative cold start forcing mechanisms

## License

This project is provided as-is for measuring AWS Lambda performance.

## Additional Resources

- [AWS Lambda Documentation](https://docs.aws.amazon.com/lambda/)
- [AWS Lambda Cold Starts](https://aws.amazon.com/blogs/compute/operating-lambda-performance-optimization-part-1/)
- [CloudWatch Logs Documentation](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/)
