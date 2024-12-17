# Weather Source Data Pipeline Infrastructure

This repository contains the Terraform configuration for deploying the Weather Source ETL infrastructure on AWS. The infrastructure is optimized for development and testing, with most services configured to stay within AWS free tier limits where possible.

## Repository Structure
```
.
├── terraform/          # Main infrastructure configuration
├── terraform-backend/  # Backend infrastructure setup
└── README.md          # This file
```

## Infrastructure Components

### Core Services
- **VPC & Networking**
  - Single private subnet and public subnets across 2 availability zones
  - NAT Gateway for private subnet internet access
  - VPC Endpoints for AWS services (S3, ECR, CloudWatch Logs, Redshift)
  - Security groups with minimal required access

- **S3 Storage**
  - Data bucket (`${environment}-weather-source-data-1`) for weather information
  - Server-side encryption enabled (AES-256)
  - Lifecycle policies for cost optimization
    - Transition to IA after 90 days
    - Transition to Glacier after 180 days

- **ECS (Elastic Container Service)**
  - Single EC2 instance cluster (t2.micro)
  - Task definitions for ETL processes:
    - Historical weather data collection
    - Weather forecast data collection
  - Scheduled tasks for three cities:
    - Washington DC (38.8552, -77.0513)
    - Paris (48.8647, 2.3490)
    - Auckland (-36.8484, 174.7633)
  - Tasks run every 2 hours starting at X:01
  - Auto Scaling Group for container management
  - CloudWatch logging enabled

- **Redshift**
  - Single-node cluster (dc2.large - free tier eligible)
  - Three-layer data architecture:
    - Bronze: Raw data landing
    - Silver: Cleaned and transformed data
    - Gold: Business-ready data
  - Automated data loading from S3
  - Scheduled data refresh every 2 hours (at X:05)
  - Secure access through VPC endpoints

### Backend Infrastructure
- **S3 State Bucket**: `terraform-state-${account_id}`
  - Versioning enabled
  - Server-side encryption (AES-256)
  - Public access blocked
  - Lifecycle policy to prevent accidental deletion

- **DynamoDB State Lock**: `terraform-state-lock`
  - Pay-per-request billing
  - Prevents concurrent state modifications

### Security Features
- All resources deployed in private subnets where possible
- Security groups with minimal required access
- Encryption enabled for data at rest and in transit
- IAM roles with least privilege access
- HTTPS/TLS for all API communications
- Credentials stored in AWS Systems Manager Parameter Store

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. AWS CLI installed and configured with appropriate credentials
2. Terraform (version >= 1.0.0) installed
3. PostgreSQL client tools installed and in PATH (required for Redshift setup)
4. An AWS account with sufficient permissions

### PostgreSQL Client Installation

#### Windows
1. Download PostgreSQL client tools from: https://www.postgresql.org/download/windows/
2. Install the client tools (you don't need the full server)
3. Add PostgreSQL bin directory to system PATH:
   ```
   C:\Program Files\PostgreSQL\<version>\bin
   ```

#### Linux
For Debian/Ubuntu:
```bash
sudo apt update
sudo apt install -y postgresql-client
```

For RHEL/CentOS/Fedora:
```bash
sudo dnf install -y postgresql
# or
sudo yum install -y postgresql
```

For Amazon Linux:
```bash
sudo yum install -y postgresql15
```

## Deployment Steps

1. **Set up Backend Infrastructure**
   ```bash
   cd terraform-backend
   terraform init
   terraform apply
   ```

2. **Initialize Main Infrastructure**
   ```bash
   cd ../terraform
   
   # For Windows (PowerShell):
   $ACCOUNT_ID = aws sts get-caller-identity --query 'Account' --output text
   terraform init -backend-config=backend.hcl -backend-config="bucket=terraform-state-$ACCOUNT_ID"
   
   # For Linux/MacOS:
   terraform init \
     -backend-config=backend.hcl \
     -backend-config="bucket=terraform-state-$(aws sts get-caller-identity --query 'Account' --output text)"
   ```

3. **Review and Apply Changes**
   ```bash
   terraform plan -var-file="env/prod.tfvars"
   terraform apply -var-file="env/prod.tfvars"
   ```

4. **Verify Redshift Setup**
   ```bash
   # Test Redshift connection (replace with your cluster endpoint)
   psql -h <cluster-endpoint> -U admin -d weather_source -p 5439
   
   # Verify schemas
   \dn
   
   # List tables
   \dt weather_source_bronze.*
   ```

## Infrastructure Management

### Monitoring
- CloudWatch Logs for ECS tasks
- Redshift query monitoring
- S3 access logs
- VPC Flow Logs

### Maintenance
- Regular updates to task definitions
- Monitoring of Redshift performance
- Review of S3 lifecycle transitions
- Security group rule reviews

### Cost Management
- Most resources within free tier limits
- S3 lifecycle policies for cost optimization
- Single-node Redshift cluster (free tier)
- Scheduled scaling for ECS tasks

## Troubleshooting

### Common Issues

1. **PostgreSQL Client Issues**
   - Ensure PostgreSQL client is installed
   - Verify PATH environment variable
   - Check Redshift security group rules

2. **ECS Task Failures**
   - Check CloudWatch Logs
   - Verify task role permissions
   - Check container resource limits

3. **Redshift Connection Issues**
   - Verify security group rules
   - Check VPC endpoint configuration
   - Validate database credentials

4. **S3 Data Loading**
   - Verify IAM role permissions
   - Check S3 bucket policies
   - Review COPY command syntax

## Important Notes

1. **Costs**: While optimized for free tier, some services may incur charges:
   - NAT Gateway ($0.045 per hour + data processing)
   - S3 storage and requests
   - Data transfer costs

2. **Security**:
   - Regularly rotate Redshift credentials
   - Monitor security group changes
   - Review IAM role permissions
   - Enable AWS CloudTrail

3. **Maintenance**:
   - Regular backups are automated
   - Monitor disk usage in Redshift
   - Review CloudWatch metrics
   - Check S3 lifecycle transitions

## Customization

The infrastructure can be customized through variables in `env/prod.tfvars`:
- AWS region (default: us-east-2)
- Environment name
- VPC CIDR ranges
- Instance types and sizes
- Redshift cluster configuration
- Monitoring and backup settings
