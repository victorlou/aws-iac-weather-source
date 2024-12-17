variable "environment" {
  description = "Deployment environment (e.g., prod, dev, staging)"
  type        = string
}

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-2"
}

variable "redshift_master_password" {
  description = "Master password for Redshift cluster"
  type        = string
  sensitive   = true
}

# Networking
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["us-east-2a", "us-east-2b"]
}

# ECS
variable "container_image_tag" {
  description = "Tag for the container image"
  type        = string
  default     = "latest"
}

# Redshift
variable "redshift_cluster_identifier" {
  description = "Identifier for the Redshift cluster"
  type        = string
  default     = "weather-source-warehouse"
}

variable "redshift_database_name" {
  description = "Name of the database to create in the Redshift cluster"
  type        = string
  default     = "weather_data"
}

variable "redshift_master_username" {
  description = "Master username for the Redshift cluster"
  type        = string
  default     = "admin"
}

variable "redshift_node_type" {
  description = "Node type for Redshift cluster"
  type        = string
  default     = "dc2.large"
}

variable "redshift_number_of_nodes" {
  description = "Number of nodes in the Redshift cluster"
  type        = number
  default     = 1
}

# CloudWatch
variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 7
}

# Tags
variable "common_tags" {
  description = "Common tags to be applied to all resources"
  type        = map(string)
  default     = {}
}

variable "private_subnet" {
  description = "Private subnet ID"
  type        = string
}

variable "weather_source_api_key" {
  description = "API key for Weather Source"
  type        = string
  sensitive   = true
}
  