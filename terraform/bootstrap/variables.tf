variable "aws_region" {
  description = "AWS region where the state bucket and lock table will live"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name prefix used in resource names"
  type        = string
  default     = "go-crud"
}
