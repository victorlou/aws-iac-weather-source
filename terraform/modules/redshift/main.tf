# Local variables for common tags
locals {
  common_tags = merge(
    var.common_tags,
    {
      Name        = "${var.environment}-weather-source"
      Environment = var.environment
    }
  )
}

# Security Group
resource "aws_security_group" "redshift" {
  name_prefix = "${var.environment}-weather-source-redshift-"
  vpc_id      = var.vpc_id
  
  ingress {
    from_port       = 5439
    to_port         = 5439
    protocol        = "tcp"
    cidr_blocks     = [data.aws_vpc.selected.cidr_block]
    description     = "Allow access from VPC"
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }
  
  tags = local.common_tags

  lifecycle {
    create_before_destroy = true
  }
}

# Subnet Group
resource "aws_redshift_subnet_group" "main" {
  name       = "${var.environment}-weather-source"
  subnet_ids = [var.private_subnet]
  
  tags = local.common_tags
}

# IAM Role for Redshift
resource "aws_iam_role" "redshift" {
  name = "${var.environment}-weather-source-redshift"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "redshift.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Policy for Redshift - Basic permissions
resource "aws_iam_role_policy" "redshift" {
  name = "${var.environment}-weather-source-redshift-policy"
  role = aws_iam_role.redshift.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:ListAllMyBuckets",
          "s3:GetBucketAcl"
        ]
        Resource = [
          "arn:aws:s3:::${var.data_bucket_name}",
          "arn:aws:s3:::${var.data_bucket_name}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = ["*"]
      }
    ]
  })
}

# Redshift Cluster - Free Tier Configuration
resource "aws_redshift_cluster" "main" {
  cluster_identifier = var.cluster_identifier
  database_name      = var.database_name
  master_username    = var.master_username
  master_password    = var.master_password
  
  node_type         = var.node_type
  number_of_nodes   = var.number_of_nodes
  
  cluster_subnet_group_name = aws_redshift_subnet_group.main.name
  vpc_security_group_ids   = [aws_security_group.redshift.id]
  
  iam_roles                = [aws_iam_role.redshift.arn]
  encrypted                = true
  skip_final_snapshot     = true
  enhanced_vpc_routing    = true  # Added for better security
  
  tags = local.common_tags
}

# Store credentials in SSM Parameter Store after cluster creation
resource "aws_ssm_parameter" "redshift_master_username" {
  name        = "/${var.environment}/redshift/master_username"
  description = "Master username for Redshift cluster"
  type        = "String"
  value       = var.master_username
  
  tags = local.common_tags

  depends_on = [aws_redshift_cluster.main]
}

resource "aws_ssm_parameter" "redshift_master_password" {
  name        = "/${var.environment}/redshift/master_password"
  description = "Master password for Redshift cluster"
  type        = "SecureString"
  value       = var.master_password
  
  tags = local.common_tags

  depends_on = [aws_redshift_cluster.main]
}

# Update IAM role to allow Redshift to access SSM parameters
resource "aws_iam_role_policy" "redshift_ssm" {
  name = "${var.environment}-weather-source-redshift-ssm"
  role = aws_iam_role.redshift.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Resource = [
          aws_ssm_parameter.redshift_master_username.arn,
          aws_ssm_parameter.redshift_master_password.arn
        ]
      }
    ]
  })
}

# Read SQL files
locals {
  setup_sql = templatefile(
    "${path.module}/scripts/setup.sql.tftpl",
    {
      environment = var.environment
    }
  )
  load_data_sql = templatefile(
    "${path.module}/scripts/load_data.sql.tftpl",
    {
      data_bucket_name = var.data_bucket_name
      redshift_role_arn = aws_iam_role.redshift.arn
      environment = var.environment
    }
  )
  transformations_sql = templatefile(
    "${path.module}/scripts/transformations.sql.tftpl",
    {
      environment = var.environment
    }
  )
}

# Create scripts directory
resource "null_resource" "scripts_dir" {
  provisioner "local-exec" {
    command = <<-EOT
      %{if substr(pathexpand("~"), 0, 1) == "/" }
        mkdir -p ${path.module}/scripts
      %{else}
        powershell -Command "New-Item -ItemType Directory -Force -Path ${path.module}/scripts"
      %{endif}
    EOT
    interpreter = substr(pathexpand("~"), 0, 1) == "/" ? ["bash", "-c"] : ["cmd.exe", "/C"]
  }
}

# Write SQL files to disk
resource "local_file" "setup_sql" {
  content  = local.setup_sql
  filename = "${path.module}/scripts/setup_generated.sql"

  depends_on = [null_resource.scripts_dir]
}

resource "local_file" "load_data_sql" {
  content  = local.load_data_sql
  filename = "${path.module}/scripts/load_data_generated.sql"

  depends_on = [null_resource.scripts_dir]
}

resource "local_file" "transformations_sql" {
  content  = local.transformations_sql
  filename = "${path.module}/scripts/transformations_generated.sql"

  depends_on = [null_resource.scripts_dir]
}

# Schema and Table Creation Command
resource "null_resource" "setup_redshift" {
  triggers = {
    cluster_endpoint = aws_redshift_cluster.main.endpoint
    setup_sql_hash = sha256(local.setup_sql)      # Trigger on setup SQL changes
    views_sql_hash = sha256(local.transformations_sql)  # Trigger on view changes
  }

  provisioner "local-exec" {
    command = <<-EOT
      %{if substr(pathexpand("~"), 0, 1) == "/" }
        # Linux/Unix
        if command -v psql >/dev/null 2>&1; then
          echo "PostgreSQL client found, proceeding with setup..."
          echo "Running setup script..."
          PGPASSWORD='${var.master_password}' psql -h ${aws_redshift_cluster.main.endpoint} -U ${var.master_username} -d ${var.database_name} -p 5439 -f "${path.module}/scripts/setup_generated.sql"
          if [ $? -ne 0 ]; then
            echo "Setup script failed!"
            exit 1
          fi
          echo "Creating views..."
          PGPASSWORD='${var.master_password}' psql -h ${aws_redshift_cluster.main.endpoint} -U ${var.master_username} -d ${var.database_name} -p 5439 -f "${path.module}/scripts/transformations_generated.sql"
          if [ $? -ne 0 ]; then
            echo "Transformations script failed!"
            exit 1
          fi
        else
          echo "WARNING: PostgreSQL client (psql) not found..."
          exit 1
        fi
      %{else}
        # Windows
        powershell -Command "
          if (Get-Command psql -ErrorAction SilentlyContinue) {
            Write-Host 'PostgreSQL client found, proceeding with setup...'
            $env:PGPASSWORD='${var.master_password}'
            psql -h ${aws_redshift_cluster.main.endpoint} -U ${var.master_username} -d ${var.database_name} -p 5439 -f '${path.module}/scripts/setup_generated.sql'
            Write-Host 'Creating views...'
            psql -h ${aws_redshift_cluster.main.endpoint} -U ${var.master_username} -d ${var.database_name} -p 5439 -f '${path.module}/scripts/transformations_generated.sql'
          } else {
            Write-Host 'WARNING: PostgreSQL client (psql) not found...'
            exit 1
          }
        "
      %{endif}
    EOT
    interpreter = substr(pathexpand("~"), 0, 1) == "/" ? ["bash", "-c"] : ["cmd.exe", "/C"]
  }

  depends_on = [
    aws_redshift_cluster.main,
    local_file.setup_sql,
    local_file.transformations_sql
  ]
}

# Get current AWS account ID
data "aws_caller_identity" "current" {}

# EventBridge rule for scheduled data loading
resource "aws_cloudwatch_event_rule" "redshift_load" {
  name                = "${var.environment}-weather-source-data-load"
  description         = "Trigger Redshift data loading every 5 minutes"
  schedule_expression = "rate(5 minutes)"       # Every 5 minutes
  
  tags = local.common_tags
}

# EventBridge target for Redshift data loading
resource "aws_cloudwatch_event_target" "redshift_load" {
  rule      = aws_cloudwatch_event_rule.redshift_load.name
  target_id = "RedshiftDataLoad"
  arn       = "arn:aws:redshift:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:cluster:${aws_redshift_cluster.main.cluster_identifier}"
  role_arn  = aws_iam_role.eventbridge.arn

  redshift_target {
    database = aws_redshift_cluster.main.database_name
    sql      = local.load_data_sql
    db_user  = var.master_username
  }

  depends_on = [
    aws_redshift_cluster.main,
    aws_iam_role.eventbridge,
    null_resource.setup_redshift
  ]
}

# Get current AWS region
data "aws_region" "current" {}

# Get Admins group data
data "aws_iam_group" "admins" {
  group_name = "Admins"
}

# Additional IAM permissions for EventBridge to invoke Redshift
resource "aws_iam_role_policy" "redshift_eventbridge" {
  name = "${var.environment}-weather-source-redshift-eventbridge"
  role = aws_iam_role.redshift.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "redshift:ExecuteQuery",
          "redshift:GetClusterCredentials",
          "redshift:CreateClusterUser"
        ]
        Resource = [
          aws_redshift_cluster.main.arn,
          "${aws_redshift_cluster.main.arn}/*"
        ]
      }
    ]
  })
}

# IAM role for EventBridge
resource "aws_iam_role" "eventbridge" {
  name = "${var.environment}-weather-source-eventbridge-${random_string.suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = [
            "events.amazonaws.com",
            "redshift.amazonaws.com",
            "scheduler.redshift.amazonaws.com"
          ]
        }
      },
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          AWS = data.aws_caller_identity.current.arn
        }
      }
    ]
  })
}

# Generate random suffix for unique names
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# IAM policy for EventBridge to execute Redshift queries
resource "aws_iam_role_policy" "eventbridge_redshift" {
  name = "${var.environment}-weather-source-eventbridge-redshift"
  role = aws_iam_role.eventbridge.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "redshift-data:ExecuteStatement",
          "redshift-data:GetStatementResult",
          "redshift-data:DescribeStatement",
          "redshift-data:ListStatements",
          "redshift-data:CancelStatement",
          "redshift-data:ListDatabases",
          "redshift-data:ListSchemas",
          "redshift-data:ListTables",
          "redshift-data:DescribeTable",
          "redshift:GetClusterCredentials",
          "redshift:DescribeClusters",
          "redshift:DescribeClusterParameters",
          "redshift:DescribeClusterParameterGroups",
          "redshift:ModifyClusterParameterGroup",
          "redshift:ResetClusterParameterGroup",
          "redshift:DescribeLoggingStatus",
          "redshift:DescribeClusterSnapshots",
          "redshift:DescribeTableRestoreStatus",
          "redshift:DescribeClusterTracks",
          "cloudwatch:PutMetricData",
          "cloudwatch:GetMetricData",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          aws_redshift_cluster.main.arn,
          "arn:aws:redshift:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_redshift_cluster.main.cluster_identifier}/${var.master_username}",
          "arn:aws:redshift:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:cluster:*",
          "arn:aws:redshift:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parametergroup:*",
          "arn:aws:redshift:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:securitygroup:*",
          "arn:aws:redshift:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:subnetgroup:*",
          "arn:aws:redshift:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:loggingstatus:*",
          "arn:aws:redshift:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:clustersnapshot:*",
          "arn:aws:redshift:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:tablerestorestatus:*",
          "arn:aws:redshift:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:clustertarget:*",
          "arn:aws:cloudwatch:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:metricdata:*",
          "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:loggroup:*",
          "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:logstream:*",
          "arn:aws:redshift:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:subnetgroup:*",
          "arn:aws:redshift:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:statement:*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "redshift-data:ListStatements",
          "redshift-data:DescribeStatement",
          "redshift-data:GetStatementResult"
        ]
        Resource = "*"
      }
    ]
  })
}

# Add policy for viewing scheduled query history
resource "aws_iam_role_policy" "eventbridge_scheduler" {
  name = "${var.environment}-weather-source-eventbridge-scheduler"
  role = aws_iam_role.eventbridge.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "redshift:DescribeScheduledActions",
          "redshift:GetScheduledQueryHistory",
          "redshift:ListScheduledQueries",
          "redshift:DescribeSchedules",
          "redshift:CreateSchedule",
          "redshift:ModifySchedule",
          "redshift:DeleteSchedule",
          "scheduler.redshift.amazonaws.com:GetSchedule",
          "scheduler.redshift.amazonaws.com:ListSchedules",
          "scheduler.redshift.amazonaws.com:CreateSchedule",
          "scheduler.redshift.amazonaws.com:DeleteSchedule",
          "scheduler.redshift.amazonaws.com:UpdateSchedule",
          "redshift:BatchGetSchedules",
          "redshift:ResumeSchedule",
          "redshift:PauseSchedule",
          "redshift-data:ExecuteStatement",
          "redshift-data:CancelStatement",
          "redshift-data:DescribeStatement",
          "redshift-data:GetStatementResult",
          "redshift-data:ListStatements",
          "redshift:GetClusterCredentials",
          "redshift:CreateScheduledAction",
          "redshift:ModifyScheduledAction",
          "redshift:DeleteScheduledAction",
          "redshift:DescribeScheduledActions"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = [
          aws_iam_role.redshift.arn,
          aws_iam_role.eventbridge.arn
        ]
      }
    ]
  })
}

# Get VPC data
data "aws_vpc" "selected" {
  id = var.vpc_id
}

# Policy for Admins to view Redshift queries
resource "aws_iam_group_policy" "admins_redshift_view" {
  name  = "${var.environment}-weather-source-redshift-view"
  group = data.aws_iam_group.admins.group_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "redshift-data:ListStatements",
          "redshift-data:DescribeStatement",
          "redshift-data:GetStatementResult",
          "redshift:DescribeSchedules",
          "redshift:GetScheduledQueryHistory",
          "redshift:ListScheduledQueries",
          "redshift-data:ListDatabases",
          "redshift-data:ListSchemas",
          "redshift-data:ListTables",
          "redshift-data:DescribeTable",
          "redshift:DescribeScheduledActions",
          "redshift:BatchGetSchedules",
          "scheduler.redshift.amazonaws.com:GetSchedule",
          "scheduler.redshift.amazonaws.com:ListSchedules",
          "logs:GetLogEvents",
          "logs:FilterLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      }
    ]
  })
}

# Add CloudWatch Logs policy for EventBridge
resource "aws_iam_role_policy" "eventbridge_logs" {
  name = "${var.environment}-weather-source-eventbridge-logs"
  role = aws_iam_role.eventbridge.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
          "logs:GetLogEvents"
        ]
        Resource = [
          "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/events/*",
          "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/redshift/*"
        ]
      }
    ]
  })
}

# Add Redshift Scheduler policy
resource "aws_iam_role_policy" "redshift_scheduler" {
  name = "${var.environment}-weather-source-redshift-scheduler"
  role = aws_iam_role.redshift.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "redshift:CreateScheduledAction",
          "redshift:ModifyScheduledAction",
          "redshift:DeleteScheduledAction",
          "redshift:DescribeScheduledActions",
          "redshift:ExecuteQuery",
          "redshift:FetchResults",
          "redshift:CancelQuery",
          "redshift:DescribeTable",
          "redshift:GetClusterCredentials",
          "redshift:GetScheduledQueryHistory",
          "redshift:ListScheduledQueries",
          "redshift:DescribeSchedules",
          "redshift:CreateSchedule",
          "redshift:ModifySchedule",
          "redshift:DeleteSchedule",
          "redshift:BatchGetSchedules",
          "redshift:ResumeSchedule",
          "redshift:PauseSchedule",
          "scheduler.redshift.amazonaws.com:GetSchedule",
          "scheduler.redshift.amazonaws.com:ListSchedules",
          "scheduler.redshift.amazonaws.com:CreateSchedule",
          "scheduler.redshift.amazonaws.com:DeleteSchedule",
          "scheduler.redshift.amazonaws.com:UpdateSchedule",
          "redshift-data:ExecuteStatement",
          "redshift-data:CancelStatement",
          "redshift-data:DescribeStatement",
          "redshift-data:GetStatementResult",
          "redshift-data:ListStatements",
          "redshift-data:ListDatabases",
          "redshift-data:ListSchemas",
          "redshift-data:ListTables",
          "redshift-data:DescribeTable"
        ]
        Resource = [
          aws_redshift_cluster.main.arn,
          "${aws_redshift_cluster.main.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:redshift/*"
        ]
      }
    ]
  })
}

# Add CloudWatch monitoring for Redshift scheduled queries
resource "aws_cloudwatch_log_group" "redshift_scheduled_queries" {
  name              = "/aws/redshift/${var.environment}/scheduled-queries"
  retention_in_days = 14

  tags = local.common_tags
}

# End of file