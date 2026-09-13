variable "env" {
  description = "Environment name (dev or prod)"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs where RDS and ElastiCache will be placed"
  type        = list(string)
}

variable "sg_rds_id" {
  description = "Security group ID to attach to the RDS instance"
  type        = string
}

variable "sg_elasticache_id" {
  description = "Security group ID to attach to the ElastiCache cluster"
  type        = string
}

variable "db_password" {
  description = "RDS master password — should come from a random_password resource in the environment"
  type        = string
  sensitive   = true
}

variable "db_instance_class" {
  description = "RDS instance type (e.g. db.t3.micro for dev, db.t3.small for prod)"
  type        = string
}

variable "multi_az" {
  description = "Enable Multi-AZ for RDS — false in dev, true in prod for high availability"
  type        = bool
}

variable "backup_retention_days" {
  description = "Number of days to retain automated RDS backups (1 for dev, 7 for prod)"
  type        = number
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot on destroy — true for dev (faster teardown), false for prod"
  type        = bool
}

variable "deletion_protection" {
  description = "Prevent accidental RDS deletion — false for dev, true for prod"
  type        = bool
}

variable "redis_node_type" {
  description = "ElastiCache node type (e.g. cache.t3.micro for dev, cache.t3.small for prod)"
  type        = string
}

variable "redis_num_nodes" {
  description = "Number of Redis nodes (1 for dev, 2 for prod)"
  type        = number
}
