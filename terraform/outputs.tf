# VPC and Networking
output "vpc_id" {
  description = "ID of the VPC"
  value       = module.networking.vpc_id
}

output "private_subnet" {
  description = "Private subnet ID"
  value       = module.networking.private_subnet
}

output "public_subnets" {
  description = "List of public subnet IDs"
  value       = module.networking.public_subnets
}

# S3
output "data_bucket_name" {
  description = "Name of the S3 bucket for weather data"
  value       = module.s3.data_bucket_name
}

output "data_bucket_arn" {
  description = "ARN of the S3 bucket for weather data"
  value       = module.s3.data_bucket_arn
}

# ECR
output "ecr_repository_url" {
  description = "URL of the ECR repository"
  value       = aws_ecr_repository.etl.repository_url
}

# ECS
output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = module.ecs.cluster_name
}

output "ecs_cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = module.ecs.cluster_arn
}

# Redshift
output "redshift_cluster_endpoint" {
  description = "Endpoint of the Redshift cluster"
  value       = module.redshift.cluster_endpoint
}

output "redshift_database_name" {
  description = "Name of the Redshift database"
  value       = module.redshift.database_name
} 