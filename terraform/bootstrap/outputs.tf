output "state_bucket_name" {
  description = "S3 bucket name to use in environment backend.tf files"
  value       = aws_s3_bucket.state.bucket
}

output "dynamodb_table_name" {
  description = "DynamoDB table name to use in environment backend.tf files"
  value       = aws_dynamodb_table.state_lock.name
}
