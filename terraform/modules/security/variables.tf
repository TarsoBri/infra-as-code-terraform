variable "env" {
  description = "Environment name (dev or prod)"
  type        = string
}

variable "db_password" {
  description = "RDS master password — stored in Secrets Manager, never logged"
  type        = string
  sensitive   = true
}

variable "db_username" {
  description = "RDS master username — stored in Secrets Manager"
  type        = string
  sensitive   = true
}

variable "s3_bucket_arn" {
  description = "ARN of the S3 assets bucket — used to grant ECS task write access"
  type        = string
}

variable "redis_endpoint" {
  description = "ElastiCache Redis endpoint — stored in SSM for the app to read at startup"
  type        = string
}

variable "github_org" {
  description = "GitHub organization or user that owns the repository"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name (without the org prefix)"
  type        = string
}
