variable "env" {
  description = "Environment name (dev or prod)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the ALB target group will be registered"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for the ALB"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for ECS tasks"
  type        = list(string)
}

variable "sg_alb_id" {
  description = "Security group ID for the ALB"
  type        = string
}

variable "sg_ecs_id" {
  description = "Security group ID for ECS tasks"
  type        = string
}

variable "ecs_execution_role_arn" {
  description = "ARN of the IAM role used by ECS to pull images and inject secrets"
  type        = string
}

variable "ecs_task_role_arn" {
  description = "ARN of the IAM role assumed by the running Go container"
  type        = string
}

variable "container_image" {
  description = "Full ECR image URI with tag (e.g. 123456789.dkr.ecr.us-east-1.amazonaws.com/go-crud-dev:latest)"
  type        = string
}

variable "task_cpu" {
  description = "Fargate task CPU units (256 for dev, 512 for prod)"
  type        = number
}

variable "task_memory" {
  description = "Fargate task memory in MB (512 for dev, 1024 for prod)"
  type        = number
}

variable "min_tasks" {
  description = "Minimum number of running ECS tasks"
  type        = number
}

variable "max_tasks" {
  description = "Maximum number of ECS tasks Auto Scaling can create"
  type        = number
}

variable "db_password_secret_arn" {
  description = "Secrets Manager ARN for the DB password — injected as DB_PASSWORD env var"
  type        = string
}

variable "db_username_secret_arn" {
  description = "Secrets Manager ARN for the DB username — injected as DB_USERNAME env var"
  type        = string
}

variable "db_endpoint" {
  description = "RDS endpoint hostname — passed as DB_HOST env var to the container"
  type        = string
}

variable "redis_endpoint" {
  description = "ElastiCache Redis hostname — passed as REDIS_ADDR env var to the container"
  type        = string
}

variable "aws_region" {
  description = "AWS region — needed for CloudWatch log configuration in the task definition"
  type        = string
}
