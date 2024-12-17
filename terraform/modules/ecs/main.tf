# Get current AWS region
data "aws_region" "current" {}

# Get current AWS account ID
data "aws_caller_identity" "current" {}

# Get VPC data
data "aws_vpc" "selected" {
  id = var.vpc_id
}

# Local variables for common tags and environment
locals {
  common_tags = {
    Name        = "${var.environment}-weather-source"
    Environment = var.environment
  }

  asg_tags = [
    for key, value in local.common_tags : {
      key                 = key
      value               = value
      propagate_at_launch = true
    }
  ]
}

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "${var.environment}-weather-source-cluster"
  
  setting {
    name  = "containerInsights"
    value = "disabled"
  }
  
  tags = local.common_tags
}

# Associate Fargate Capacity Provider with Cluster
resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = ["FARGATE"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}

# Security Group for VPC Endpoints
resource "aws_security_group" "vpc_endpoints" {
  name_prefix = "${var.environment}-vpc-endpoints-"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  tags = merge(local.common_tags, {
    Name = "${var.environment}-vpc-endpoints"
  })
}

# Add data source to get subnet information
data "aws_subnet" "private" {
  id = var.private_subnet
} 

resource "aws_ecs_task_definition" "historical_etl_dc" {
  family                = "${var.environment}-weather-source-historical-etl-dc"
  network_mode         = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  task_role_arn        = aws_iam_role.ecs_task.arn
  execution_role_arn   = aws_iam_role.ecs_task_execution.arn
  memory               = 512
  cpu                  = 256

  container_definitions = jsonencode([
    {
      name      = "weather-source-historical-etl-dc"
      image     = "${var.ecr_repository_url}:${var.container_image_tag}"
      memory    = 450
      cpu       = 256
      essential = true
      entryPoint = ["/bin/sh", "-c"],
      command = [
        join(" ", [
          "python src/main.py",
          "--latitude 38.8552",
          "--longitude -77.0513",
          "--data-type historical",
          "--start-date $(date -d 'yesterday' '+%Y-%m-%d')",
          "--end-date $(date '+%Y-%m-%d')",
          "--fields all",
          "--file-format parquet",
          "--use-s3"
        ])
      ],
      
      environment = [
        {
          name  = "ENVIRONMENT"
          value = var.environment
        },
        {
          name  = "S3_BUCKET_NAME"
          value = var.data_bucket_name
        },
        {
          name  = "AWS_REGION"
          value = var.aws_region
        },
        {
          name  = "LOG_LEVEL"
          value = "DEBUG"
        },
        {
          name  = "WEATHER_SOURCE_API_KEY"
          value = var.weather_source_api_key
        },
        {
          name  = "DATA_OUTPUT_PATH"
          value = "/tmp/data"
        }
      ],
      
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs.name
          awslogs-region        = data.aws_region.current.name
          awslogs-stream-prefix = "historical-dc"
        }
      }
    }
  ])
}

resource "aws_cloudwatch_event_target" "historical_target_dc" {
  rule      = aws_cloudwatch_event_rule.historical_schedule.name
  target_id = "HistoricalECSTaskDC"
  arn       = aws_ecs_cluster.main.arn
  role_arn  = aws_iam_role.eventbridge.arn

  ecs_target {
    task_count          = 1
    task_definition_arn = aws_ecs_task_definition.historical_etl_dc.arn
    launch_type         = "FARGATE"
    network_configuration {
      subnets          = [var.private_subnet]
      security_groups  = [aws_security_group.ecs_tasks.id]
      assign_public_ip = false
    }
  }
}

resource "aws_security_group" "ecs_tasks" {
  name_prefix = "${var.environment}-weather-source-tasks-"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow Redshift access
  ingress {
    from_port   = 5439
    to_port     = 5439
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.selected.cidr_block]  # Allow from entire VPC
  }

  tags = local.common_tags
}

# ECS Task Role
resource "aws_iam_role" "ecs_task" {
  name = "${var.environment}-weather-source-ecs-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

# Add S3 permissions to task role
resource "aws_iam_role_policy" "ecs_task_s3" {
  name = "${var.environment}-weather-source-ecs-task-s3"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:CreateLogGroup",
          "logs:DescribeLogStreams"
        ]
        Resource = ["${aws_cloudwatch_log_group.ecs.arn}:*"]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:DeleteObject"
        ]
        Resource = [
          var.data_bucket_arn,
          "${var.data_bucket_arn}/*"
        ]
      }
    ]
  })
}

# ECS Task Execution Role
resource "aws_iam_role" "ecs_task_execution" {
  name = "${var.environment}-weather-source-ecs-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

# Attach policies to execution role
resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${var.environment}-weather-source"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

# EventBridge IAM Role
resource "aws_iam_role" "eventbridge" {
  name = "${var.environment}-weather-source-eventbridge"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
      }
    ]
  })
}

# Add policy for EventBridge to run ECS tasks
resource "aws_iam_role_policy" "eventbridge_ecs" {
  name = "${var.environment}-weather-source-eventbridge-ecs"
  role = aws_iam_role.eventbridge.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecs:RunTask",
          "ecs:StopTask",
          "ecs:DescribeTasks",
          "ecs:ListTasks",
          "ecs:DescribeTaskDefinition",
          "ecs:RegisterTaskDefinition",
          "ecs:ListTaskDefinitions",
          "ecs:DescribeClusters",
          "ecs:ListClusters"
        ]
        Resource = [
          aws_ecs_cluster.main.arn,
          "${aws_ecs_cluster.main.arn}/*",
          aws_ecs_task_definition.historical_etl_dc.arn,
          aws_ecs_task_definition.historical_etl_paris.arn,
          aws_ecs_task_definition.historical_etl_auckland.arn,
          aws_ecs_task_definition.forecast_etl_dc.arn,
          aws_ecs_task_definition.forecast_etl_paris.arn,
          aws_ecs_task_definition.forecast_etl_auckland.arn,
          "arn:aws:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:task/*",
          "arn:aws:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:task-definition/*:*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole",
          "iam:GetRole",
          "iam:ListRoles",
          "iam:ListInstanceProfiles"
        ]
        Resource = [
          aws_iam_role.ecs_task.arn,
          aws_iam_role.ecs_task_execution.arn,
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:CreateLogGroup",
          "logs:DescribeLogStreams",
          "logs:DescribeLogGroups"
        ]
        Resource = [
          "${aws_cloudwatch_log_group.ecs.arn}:*",
          "${aws_cloudwatch_log_group.ecs.arn}:*:*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeVpcs"
        ]
        Resource = ["*"]
      }
    ]
  })
}

# Historical Data Schedule Rule (Daily at 00:01)
resource "aws_cloudwatch_event_rule" "historical_schedule" {
  name                = "${var.environment}-weather-source-historical-schedule"
  description         = "Schedule for historical weather data collection"
  schedule_expression = "rate(5 minutes)"     # Every 5 minutes
  
  tags = local.common_tags
}

# Paris Historical Task
resource "aws_ecs_task_definition" "historical_etl_paris" {
  family                = "${var.environment}-weather-source-historical-etl-paris"
  network_mode         = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  task_role_arn        = aws_iam_role.ecs_task.arn
  execution_role_arn   = aws_iam_role.ecs_task_execution.arn
  memory               = 512
  cpu                  = 256

  container_definitions = jsonencode([
    {
      name      = "weather-source-historical-etl-paris"
      image     = "${var.ecr_repository_url}:${var.container_image_tag}"
      memory    = 450
      cpu       = 256
      essential = true
      
      entryPoint = ["/bin/sh", "-c"],
      command = [
        join(" ", [
          "python src/main.py",
          "--latitude 48.8647",
          "--longitude 2.3490",
          "--data-type historical",
          "--start-date $(date -d 'yesterday' '+%Y-%m-%d')",
          "--end-date $(date '+%Y-%m-%d')",
          "--fields all",
          "--file-format parquet",
          "--use-s3"
        ])
      ],
      
      environment = [
        {
          name  = "ENVIRONMENT"
          value = var.environment
        },
        {
          name  = "S3_BUCKET_NAME"
          value = var.data_bucket_name
        },
        {
          name  = "AWS_REGION"
          value = var.aws_region
        },
        {
          name  = "LOG_LEVEL"
          value = "DEBUG"
        },
        {
          name  = "WEATHER_SOURCE_API_KEY"
          value = var.weather_source_api_key
        },
        {
          name  = "DATA_OUTPUT_PATH"
          value = "/tmp/data"
        }
      ],
      
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs.name
          awslogs-region        = data.aws_region.current.name
          awslogs-stream-prefix = "historical-paris"
        }
      }
    }
  ])
}

# Auckland Historical Task
resource "aws_ecs_task_definition" "historical_etl_auckland" {
  family                = "${var.environment}-weather-source-historical-etl-auckland"
  network_mode         = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  task_role_arn        = aws_iam_role.ecs_task.arn
  execution_role_arn   = aws_iam_role.ecs_task_execution.arn
  memory               = 512
  cpu                  = 256

  container_definitions = jsonencode([
    {
      name      = "weather-source-historical-etl-auckland"
      image     = "${var.ecr_repository_url}:${var.container_image_tag}"
      memory    = 450
      cpu       = 256
      essential = true
      
      entryPoint = ["/bin/sh", "-c"],
      command = [
        join(" ", [
          "python src/main.py",
          "--latitude -36.8484",
          "--longitude 174.7633",
          "--data-type historical",
          "--start-date $(date -d 'yesterday' '+%Y-%m-%d')",
          "--end-date $(date '+%Y-%m-%d')",
          "--fields all",
          "--file-format parquet",
          "--use-s3"
        ])
      ],
      
      environment = [
        {
          name  = "ENVIRONMENT"
          value = var.environment
        },
        {
          name  = "S3_BUCKET_NAME"
          value = var.data_bucket_name
        },
        {
          name  = "AWS_REGION"
          value = var.aws_region
        },
        {
          name  = "LOG_LEVEL"
          value = "DEBUG"
        },
        {
          name  = "WEATHER_SOURCE_API_KEY"
          value = var.weather_source_api_key
        },
        {
          name  = "DATA_OUTPUT_PATH"
          value = "/tmp/data"
        }
      ],
      
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs.name
          awslogs-region        = data.aws_region.current.name
          awslogs-stream-prefix = "historical-auckland"
        }
      }
    }
  ])
}

# Forecast Tasks
resource "aws_ecs_task_definition" "forecast_etl_dc" {
  family                = "${var.environment}-weather-source-forecast-etl-dc"
  network_mode         = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  task_role_arn        = aws_iam_role.ecs_task.arn
  execution_role_arn   = aws_iam_role.ecs_task_execution.arn
  memory               = 512
  cpu                  = 256

  container_definitions = jsonencode([
    {
      name      = "weather-source-forecast-etl-dc"
      image     = "${var.ecr_repository_url}:${var.container_image_tag}"
      memory    = 450
      cpu       = 256
      essential = true
      
      entryPoint = ["/bin/sh", "-c"],
      command = [
        join(" ", [
          "python src/main.py",
          "--latitude 38.8552",
          "--longitude -77.0513",
          "--data-type forecast",
          "--start-date $(date '+%Y-%m-%d')",
          "--end-date $(date -d '+7 days' '+%Y-%m-%d')",
          "--fields all",
          "--file-format parquet",
          "--use-s3"
        ])
      ],
      
      environment = [
        {
          name  = "ENVIRONMENT"
          value = var.environment
        },
        {
          name  = "S3_BUCKET_NAME"
          value = var.data_bucket_name
        },
        {
          name  = "AWS_REGION"
          value = var.aws_region
        },
        {
          name  = "LOG_LEVEL"
          value = "DEBUG"
        },
        {
          name  = "WEATHER_SOURCE_API_KEY"
          value = var.weather_source_api_key
        },
        {
          name  = "DATA_OUTPUT_PATH"
          value = "/tmp/data"
        }
      ],
      
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs.name
          awslogs-region        = data.aws_region.current.name
          awslogs-stream-prefix = "forecast-dc"
        }
      }
    }
  ])
}

# Paris Forecast Task
resource "aws_ecs_task_definition" "forecast_etl_paris" {
  family                = "${var.environment}-weather-source-forecast-etl-paris"
  network_mode         = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  task_role_arn        = aws_iam_role.ecs_task.arn
  execution_role_arn   = aws_iam_role.ecs_task_execution.arn
  memory               = 512
  cpu                  = 256

  container_definitions = jsonencode([
    {
      name      = "weather-source-forecast-etl-paris"
      image     = "${var.ecr_repository_url}:${var.container_image_tag}"
      memory    = 450
      cpu       = 256
      essential = true
      
      entryPoint = ["/bin/sh", "-c"],
      command = [
        join(" ", [
          "python src/main.py",
          "--latitude 48.8647",
          "--longitude 2.3490",
          "--data-type forecast",
          "--start-date $(date '+%Y-%m-%d')",
          "--end-date $(date -d '+7 days' '+%Y-%m-%d')",
          "--fields all",
          "--file-format parquet",
          "--use-s3"
        ])
      ],
      
      environment = [
        {
          name  = "ENVIRONMENT"
          value = var.environment
        },
        {
          name  = "S3_BUCKET_NAME"
          value = var.data_bucket_name
        },
        {
          name  = "AWS_REGION"
          value = var.aws_region
        },
        {
          name  = "LOG_LEVEL"
          value = "DEBUG"
        },
        {
          name  = "WEATHER_SOURCE_API_KEY"
          value = var.weather_source_api_key
        },
        {
          name  = "DATA_OUTPUT_PATH"
          value = "/tmp/data"
        }
      ],
      
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs.name
          awslogs-region        = data.aws_region.current.name
          awslogs-stream-prefix = "forecast-paris"
        }
      }
    }
  ])
}

# Auckland Forecast Task
resource "aws_ecs_task_definition" "forecast_etl_auckland" {
  family                = "${var.environment}-weather-source-forecast-etl-auckland"
  network_mode         = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  task_role_arn        = aws_iam_role.ecs_task.arn
  execution_role_arn   = aws_iam_role.ecs_task_execution.arn
  memory               = 512
  cpu                  = 256

  container_definitions = jsonencode([
    {
      name      = "weather-source-forecast-etl-auckland"
      image     = "${var.ecr_repository_url}:${var.container_image_tag}"
      memory    = 450
      cpu       = 256
      essential = true
      
      entryPoint = ["/bin/sh", "-c"],
      command = [
        join(" ", [
          "python src/main.py",
          "--latitude -36.8484",
          "--longitude 174.7633",
          "--data-type forecast",
          "--start-date $(date '+%Y-%m-%d')",
          "--end-date $(date -d '+7 days' '+%Y-%m-%d')",
          "--fields all",
          "--file-format parquet",
          "--use-s3"
        ])
      ],
      
      environment = [
        {
          name  = "ENVIRONMENT"
          value = var.environment
        },
        {
          name  = "S3_BUCKET_NAME"
          value = var.data_bucket_name
        },
        {
          name  = "AWS_REGION"
          value = var.aws_region
        },
        {
          name  = "LOG_LEVEL"
          value = "DEBUG"
        },
        {
          name  = "WEATHER_SOURCE_API_KEY"
          value = var.weather_source_api_key
        },
        {
          name  = "DATA_OUTPUT_PATH"
          value = "/tmp/data"
        }
      ],
      
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs.name
          awslogs-region        = data.aws_region.current.name
          awslogs-stream-prefix = "forecast-auckland"
        }
      }
    }
  ])
}

# Historical Task Targets
resource "aws_cloudwatch_event_target" "historical_target_paris" {
  rule      = aws_cloudwatch_event_rule.historical_schedule.name
  target_id = "HistoricalECSTaskParis"
  arn       = aws_ecs_cluster.main.arn
  role_arn  = aws_iam_role.eventbridge.arn

  ecs_target {
    task_count          = 1
    task_definition_arn = aws_ecs_task_definition.historical_etl_paris.arn
    launch_type         = "FARGATE"
    network_configuration {
      subnets          = [var.private_subnet]
      security_groups  = [aws_security_group.ecs_tasks.id]
      assign_public_ip = false
    }
  }
}

resource "aws_cloudwatch_event_target" "historical_target_auckland" {
  rule      = aws_cloudwatch_event_rule.historical_schedule.name
  target_id = "HistoricalECSTaskAuckland"
  arn       = aws_ecs_cluster.main.arn
  role_arn  = aws_iam_role.eventbridge.arn

  ecs_target {
    task_count          = 1
    task_definition_arn = aws_ecs_task_definition.historical_etl_auckland.arn
    launch_type         = "FARGATE"
    network_configuration {
      subnets          = [var.private_subnet]
      security_groups  = [aws_security_group.ecs_tasks.id]
      assign_public_ip = false
    }
  }
}

# Forecast Schedule Rule
resource "aws_cloudwatch_event_rule" "forecast_schedule" {
  name                = "${var.environment}-weather-source-forecast-schedule"
  description         = "Schedule for forecast weather data collection"
  schedule_expression = "rate(5 minutes)"       # Every 5 minutes
  
  tags = local.common_tags
}

# Forecast Task Targets
resource "aws_cloudwatch_event_target" "forecast_target_dc" {
  rule      = aws_cloudwatch_event_rule.forecast_schedule.name
  target_id = "ForecastECSTaskDC"
  arn       = aws_ecs_cluster.main.arn
  role_arn  = aws_iam_role.eventbridge.arn

  ecs_target {
    task_count          = 1
    task_definition_arn = aws_ecs_task_definition.forecast_etl_dc.arn
    launch_type         = "FARGATE"
    network_configuration {
      subnets          = [var.private_subnet]
      security_groups  = [aws_security_group.ecs_tasks.id]
      assign_public_ip = false
    }
  }
}

resource "aws_cloudwatch_event_target" "forecast_target_paris" {
  rule      = aws_cloudwatch_event_rule.forecast_schedule.name
  target_id = "ForecastECSTaskParis"
  arn       = aws_ecs_cluster.main.arn
  role_arn  = aws_iam_role.eventbridge.arn

  ecs_target {
    task_count          = 1
    task_definition_arn = aws_ecs_task_definition.forecast_etl_paris.arn
    launch_type         = "FARGATE"
    network_configuration {
      subnets          = [var.private_subnet]
      security_groups  = [aws_security_group.ecs_tasks.id]
      assign_public_ip = false
    }
  }
}

resource "aws_cloudwatch_event_target" "forecast_target_auckland" {
  rule      = aws_cloudwatch_event_rule.forecast_schedule.name
  target_id = "ForecastECSTaskAuckland"
  arn       = aws_ecs_cluster.main.arn
  role_arn  = aws_iam_role.eventbridge.arn

  ecs_target {
    task_count          = 1
    task_definition_arn = aws_ecs_task_definition.forecast_etl_auckland.arn
    launch_type         = "FARGATE"
    network_configuration {
      subnets          = [var.private_subnet]
      security_groups  = [aws_security_group.ecs_tasks.id]
      assign_public_ip = false
    }
  }
}