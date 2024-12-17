variable "environment" {
  description = "Environment name"
  type        = string
}

variable "ecs_task_role_arn" {
  description = "ARN of the ECS task role"
  type        = string
}

variable "redshift_role_arn" {
  description = "ARN of the Redshift role for S3 access"
  type        = string
} 