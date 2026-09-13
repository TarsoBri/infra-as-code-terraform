variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "db_password" {
  description = "RDS master password — provide via terraform.tfvars, never hardcode"
  type        = string
  sensitive   = true
}

variable "db_username" {
  description = "RDS master username — provide via terraform.tfvars"
  type        = string
  sensitive   = true
}

variable "github_org" {
  description = "GitHub organization or user that owns this repository"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name (without the org prefix)"
  type        = string
}
