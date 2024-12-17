output "cluster_endpoint" {
  description = "Endpoint for Redshift cluster"
  value       = aws_redshift_cluster.main.endpoint
}

output "cluster_port" {
  description = "Port for Redshift cluster"
  value       = "5439"
}

output "security_group_id" {
  description = "ID of the Redshift security group"
  value       = aws_security_group.redshift.id
}

output "setup_script_path" {
  description = "Path to the Redshift setup SQL script"
  value       = local_file.setup_sql.filename
}

output "load_data_script_path" {
  description = "Path to the Redshift data loading SQL script"
  value       = local_file.load_data_sql.filename
}

output "database_name" {
  description = "Name of the Redshift database"
  value       = aws_redshift_cluster.main.database_name
}

output "cluster_identifier" {
  description = "Identifier of the Redshift cluster"
  value       = aws_redshift_cluster.main.id
}

output "iam_role_arn" {
  description = "ARN of the Redshift IAM role"
  value       = aws_iam_role.redshift.arn
}

output "cluster_arn" {
  description = "ARN of the Redshift cluster"
  value       = aws_redshift_cluster.main.arn
} 