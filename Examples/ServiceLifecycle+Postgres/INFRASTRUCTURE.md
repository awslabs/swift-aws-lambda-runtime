# Infrastructure Architecture

This document describes the AWS infrastructure deployed by the ServiceLifecycle example's SAM template.

## Overview

The infrastructure consists of a secure VPC setup with private subnets only, containing both the PostgreSQL RDS instance and Lambda function. The architecture is optimized for cost and security with complete network isolation.

## Network Architecture

### VPC Configuration
- **VPC**: Custom VPC with CIDR block `10.0.0.0/16`
- **DNS Support**: DNS hostnames and DNS resolution enabled

### Subnet Layout
- **Private Subnets**:
  - Private Subnet 1: `10.0.3.0/24` (AZ 1)
  - Private Subnet 2: `10.0.4.0/24` (AZ 2)
  - Used for RDS PostgreSQL database and Lambda function
  - No public IP addresses assigned
  - Complete isolation from internet

### Network Components
- **VPC-only architecture**: No internet connectivity required
- **Route Tables**: Default VPC routing for internal communication

## Security Groups

### Lambda Security Group
- **Outbound Rules**:
  - PostgreSQL (5432): Restricted to VPC CIDR `10.0.0.0/16`

### Database Security Group
- **Inbound Rules**:
  - PostgreSQL (5432): Only allows connections from the Lambda Security Group

## Database Configuration

### PostgreSQL RDS Instance
- **Instance Type**: `db.t3.micro` (cost-optimized)
- **Engine**: PostgreSQL 15.7
- **Storage**: 20GB GP2 (SSD)
- **Network**: Deployed in private subnets with no public access
- **Security**:
  - Storage encryption enabled
  - SSL/TLS connections supported
  - Credentials stored in AWS Secrets Manager
- **High Availability**: Multi-AZ disabled (development configuration)
- **Backup**: Automated backups disabled (development configuration)

### Database Subnet Group
- Spans both private subnets for availability

## Lambda Function Configuration

### Service Lifecycle Lambda
- **Runtime**: Custom runtime (provided.al2023)
- **Architecture**: ARM64
- **Memory**: 128MB
- **Timeout**: 60 seconds
- **Network**: Deployed in private subnets with access to database within VPC
- **Environment Variables**:
  - `LOG_LEVEL`: trace
  - `DB_HOST`: RDS endpoint address
  - `DB_USER`: Retrieved from Secrets Manager
  - `DB_PASSWORD`: Retrieved from Secrets Manager
  - `DB_NAME`: Database name from parameter

## API Gateway

- **Type**: HTTP API
- **Integration**: Direct Lambda integration
- **Authentication**: None (for demonstration purposes)

## Secrets Management

### Database Credentials
- **Storage**: AWS Secrets Manager
- **Secret Name**: `{StackName}-db-credentials`
- **Content**:
  - Username: "postgres"
  - Password: Auto-generated 16-character password
  - Special characters excluded: `"@/\`

## SAM Outputs

The template provides several outputs to facilitate working with the deployed resources:

- **APIGatewayEndpoint**: URL to invoke the Lambda function
- **DatabaseEndpoint**: Hostname for the PostgreSQL instance
- **DatabasePort**: Port number for PostgreSQL (5432)
- **DatabaseName**: Name of the created database
- **DatabaseSecretArn**: ARN of the secret containing credentials
- **DatabaseConnectionInstructions**: Instructions for retrieving connection details
- **ConnectionDetails**: Consolidated connection information

## Security Considerations

This infrastructure implements several security best practices:

1. **Complete Network Isolation**: Both database and Lambda are in private subnets with no direct acces to or from the internet
2. **Least Privilege**: Security groups restrict traffic to only necessary ports and sources
3. **Encryption**: Database storage is encrypted at rest
4. **Secure Credentials**: Database credentials are managed through AWS Secrets Manager
5. **Secure Communication**: Lambda function connects to database over encrypted connections

## Cost Analysis

### Monthly Cost Breakdown (US East 1 Region)

#### Billable AWS Resources:

**1. RDS PostgreSQL Database**
- Instance (db.t3.micro): $13.87/month (730 hours × $0.019/hour)
- Storage (20GB GP2): $2.30/month (20GB × $0.115/GB/month)
- Backup Storage: $0 (BackupRetentionPeriod: 0)
- Multi-AZ: $0 (disabled)
- **RDS Subtotal: $16.17/month**

**2. AWS Secrets Manager**
- Secret Storage: $0.40/month per secret
- API Calls: ~$0.05 per 10,000 calls (minimal for Lambda access)
- **Secrets Manager Subtotal: ~$0.45/month**

**3. AWS Lambda**
- Memory: 512MB ARM64
- Free Tier: 1M requests + 400,000 GB-seconds/month
- Development Usage: $0 (within free tier)
- **Lambda Subtotal: $0/month**

**4. API Gateway (HTTP API)**
- Free Tier: 1M requests/month
- Development Usage: $0 (within free tier)
- **API Gateway Subtotal: $0/month**

#### Free AWS Resources:
- VPC, Private Subnets, Security Groups, DB Subnet Group: $0

### Total Monthly Cost:

| Service | Cost | Notes |
|---------|------|---------|
| RDS PostgreSQL | $16.17 | db.t3.micro + 20GB storage |
| Secrets Manager | $0.45 | 1 secret + minimal API calls |
| Lambda | $0.00 | Within free tier |
| API Gateway | $0.00 | Within free tier |
| VPC Components | $0.00 | No charges |
| **TOTAL** | **$16.62/month** | |

### With RDS Free Tier (First 12 Months):
- RDS Instance: $0 (750 hours/month free)
- RDS Storage: $0 (20GB free)
- **Total with Free Tier: ~$0.45/month**

### Production Scaling Estimates:
- Higher Lambda usage: +$0.20 per million requests
- More RDS storage: +$0.115 per additional GB/month
- Multi-AZ RDS: ~2x RDS instance cost
- Backup storage: $0.095/GB/month

This architecture provides maximum cost efficiency while maintaining security and functionality for development workloads.