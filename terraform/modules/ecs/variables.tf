variable "environment" {
  description = "Environment name"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "private_subnet" {
  description = "Private subnet ID for ECS instances"
  type        = string
}

variable "ecr_repository_url" {
  description = "URL of the ECR repository"
  type        = string
}

variable "container_image_tag" {
  description = "Tag of the container image to deploy"
  type        = string
}

variable "data_bucket_arn" {
  description = "ARN of the S3 bucket for data storage"
  type        = string
}

variable "data_bucket_name" {
  description = "Name of the S3 bucket for data storage"
  type        = string
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 7
}

variable "weather_source_api_key" {
  description = "API key for Weather Source"
  type        = string
  sensitive   = true
} 