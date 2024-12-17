variable "environment" {
  description = "Environment name (e.g., prod, dev, staging)"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC where Redshift cluster will be created"
  type        = string
}

variable "private_subnet" {
  description = "Private subnet ID"
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

variable "log_bucket_name" {
  description = "Name of the S3 bucket for Redshift logs"
  type        = string
}

variable "cluster_identifier" {
  description = "Identifier for the Redshift cluster"
  type        = string
}

variable "database_name" {
  description = "Name of the initial database"
  type        = string
}

variable "master_username" {
  description = "Master username for Redshift cluster"
  type        = string
}

variable "master_password" {
  description = "Master password for Redshift cluster"
  type        = string
  sensitive   = true
}

variable "readonly_username" {
  description = "Read-only username for Redshift cluster"
  type        = string
  default     = null
}

variable "readonly_password" {
  description = "Read-only user password for Redshift cluster"
  type        = string
  sensitive   = true
  default     = null
}

variable "node_type" {
  description = "The node type to be provisioned for the cluster"
  type        = string
  default     = "dc2.large"
}

variable "number_of_nodes" {
  description = "Number of nodes in the cluster. For free tier use 1"
  type        = number
  default     = 1
}

variable "common_tags" {
  description = "Common tags to be applied to all resources"
  type        = map(string)
  default     = {}
} 