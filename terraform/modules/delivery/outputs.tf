output "cloudfront_domain" {
  description = "CloudFront distribution domain name for serving assets"
  value       = aws_cloudfront_distribution.main.domain_name
}

output "s3_bucket_name" {
  description = "S3 bucket name for uploading assets"
  value       = aws_s3_bucket.main.bucket
}

output "s3_bucket_arn" {
  description = "S3 bucket ARN — passed to security module to grant ECS task write access"
  value       = aws_s3_bucket.main.arn
}
