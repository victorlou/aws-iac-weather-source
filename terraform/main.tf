terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {}
}

# Define common tags as locals
locals {
  common_tags = {
    Project     = "weather-source-etl"
    Environment = var.environment
    Terraform   = "true"
    ManagedBy   = "terraform"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

# VPC and Networking
module "networking" {
  source = "./modules/networking"

  environment        = var.environment
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
  aws_region         = var.aws_region
  common_tags        = local.common_tags
}

# S3 Buckets
module "s3" {
  source = "./modules/s3"

  environment       = var.environment
  ecs_task_role_arn = module.ecs.task_role_arn
  redshift_role_arn = module.redshift.iam_role_arn
}

# ECR Repository
resource "aws_ecr_repository" "etl" {
  name                 = "weather-source-etl"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# ECS Cluster and Task
module "ecs" {
  source = "./modules/ecs"

  environment                = var.environment
  aws_region                = var.aws_region
  vpc_id                    = module.networking.vpc_id
  private_subnet            = module.networking.private_subnet
  ecr_repository_url        = aws_ecr_repository.etl.repository_url
  container_image_tag       = var.container_image_tag
  data_bucket_arn          = module.s3.data_bucket_arn
  data_bucket_name         = module.s3.data_bucket_name
  weather_source_api_key    = var.weather_source_api_key
}

# Redshift Cluster
module "redshift" {
  source = "./modules/redshift"

  environment           = var.environment
  vpc_id                = module.networking.vpc_id
  private_subnet        = module.networking.private_subnet
  data_bucket_arn       = module.s3.data_bucket_arn
  data_bucket_name      = module.s3.data_bucket_name
  log_bucket_name       = module.s3.data_bucket_name

  cluster_identifier = var.redshift_cluster_identifier
  database_name      = var.redshift_database_name
  master_username    = var.redshift_master_username
  master_password    = var.redshift_master_password
  node_type          = var.redshift_node_type
  number_of_nodes    = var.redshift_number_of_nodes

  common_tags = local.common_tags
} 