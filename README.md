# Weather Source Data Pipeline Infrastructure

This repository contains the Terraform configuration for deploying the Weather Source ETL infrastructure on AWS. The infrastructure is optimized for development and testing, with most services configured to stay within AWS free tier limits where possible.

## Repository Structure
```
.
├── terraform/          # Main infrastructure configuration
│   ├── modules/       # Reusable infrastructure modules
│   ├── env/          # Environment-specific configurations
│   │   └── template.tfvars  # Template for terraform.tfvars
│   └── *.tf          # Main Terraform configurations
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
  - Fargate tasks for ETL processes
  - Task definitions for:
    - Historical weather data collection
    - Weather forecast data collection
  - Scheduled tasks for three cities:
    - Washington DC (38.8552, -77.0513)
    - Paris (48.8647, 2.3490)
    - Auckland (-36.8484, 174.7633)
  - Tasks run every 5 minutes
  - CloudWatch logging enabled

- **Redshift**
  - Single-node cluster (dc2.large - free tier eligible)
  - Three-layer data architecture:
    - Bronze: Raw data landing
    - Silver: Cleaned and transformed data
    - Gold: Business-ready data
  - Automated data loading from S3
  - Scheduled data refresh every 5 minutes
  - Secure access through VPC endpoints

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. AWS CLI installed and configured with appropriate credentials
2. Terraform (version >= 1.0.0) installed
3. PostgreSQL client tools installed (for Redshift setup)
4. An AWS account with sufficient permissions

### Configuration Setup

A template file is provided at `terraform/env/template.tfvars` with all required variables and their descriptions. To get started:

1. Copy the template to create your configuration:
   ```bash
   cp terraform/env/template.tfvars terraform/terraform.tfvars
   ```

2. Edit `terraform.tfvars` and fill in the required values:
   - `private_subnet`: Your VPC's private subnet ID
   - `weather_source_api_key`: Your Weather Source API key
   - `redshift_master_password`: A strong password for Redshift
   - Optionally modify other values as needed

The template is preconfigured with free tier compatible defaults where possible.

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
   terraform plan
   terraform apply
   ```

## Post-Deployment Verification

1. **Verify ECS Tasks**
   ```bash
   aws ecs list-tasks --cluster <cluster-name>
   ```

2. **Check Redshift Connection**
   ```bash
   psql -h <cluster-endpoint> -U admin -d weather_source -p 5439
   ```

3. **Verify Data Flow**
   ```sql
   -- Check bronze layer tables
   SELECT COUNT(*) FROM prod_weather_source_bronze.historical;
   SELECT COUNT(*) FROM prod_weather_source_bronze.forecast;
   
   -- Check latest data
   SELECT MAX(timestamp_utc) FROM prod_weather_source_bronze.historical;
   ```

## Troubleshooting

### Common Issues

1. **ECS Task Failures**
   - Check CloudWatch Logs at `/aws/ecs/${environment}-weather-source`
   - Verify task role permissions
   - Check container resource limits

2. **Redshift Connection Issues**
   - Verify security group rules
   - Check VPC endpoint configuration
   - Validate database credentials

3. **Data Loading Issues**
   - Check S3 bucket permissions
   - Verify IAM role permissions
   - Review CloudWatch logs for Redshift scheduled queries

### Useful Commands

```bash
# Check ECS task status
aws ecs list-tasks --cluster <cluster-name>

# View CloudWatch logs
aws logs get-log-events --log-group-name /aws/ecs/prod-weather-source

# Check Redshift query history
aws redshift-data list-statements
```

## Security Notes

1. **Credentials Management**
   - Redshift passwords are stored in AWS Systems Manager Parameter Store
   - API keys are passed through environment variables
   - All sensitive data is encrypted at rest

2. **Network Security**
   - All services run in private subnets
   - Access controlled via security groups
   - VPC endpoints used for AWS service access

3. **Monitoring**
   - CloudWatch logs enabled for all services
   - Redshift query logging active
   - VPC Flow Logs available for network monitoring

## Cost Management

Most services are configured to stay within AWS free tier limits:
- Redshift: Single dc2.large node
- ECS: Fargate tasks with minimal resources
- S3: Lifecycle policies for cost optimization
- CloudWatch: 7-day log retention

Monitor costs through AWS Cost Explorer and set up billing alarms if needed.
