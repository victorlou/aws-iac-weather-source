output "data_bucket_name" {
  description = "Name of the S3 bucket for weather data"
  value       = aws_s3_bucket.data.id
}

output "data_bucket_arn" {
  description = "ARN of the S3 bucket for weather data"
  value       = aws_s3_bucket.data.arn
} 