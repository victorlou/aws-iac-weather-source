output "cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

output "cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = aws_ecs_cluster.main.arn
}

output "task_role_arn" {
  description = "ARN of the ECS task role"
  value       = aws_iam_role.ecs_task.arn
}

# Task Definition ARNs for each city
output "historical_task_definition_arns" {
  description = "ARNs of the historical weather data task definitions"
  value = {
    washington_dc = aws_ecs_task_definition.historical_etl_dc.arn
    paris        = aws_ecs_task_definition.historical_etl_paris.arn
    auckland     = aws_ecs_task_definition.historical_etl_auckland.arn
  }
}

output "forecast_task_definition_arns" {
  description = "ARNs of the forecast weather data task definitions"
  value = {
    washington_dc = aws_ecs_task_definition.forecast_etl_dc.arn
    paris        = aws_ecs_task_definition.forecast_etl_paris.arn
    auckland     = aws_ecs_task_definition.forecast_etl_auckland.arn
  }
}

output "log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.ecs.name
}

output "log_group_arn" {
  description = "ARN of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.ecs.arn
} 