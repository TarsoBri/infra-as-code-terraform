# DB subnet group — tells RDS which subnets it is allowed to place instances in
resource "aws_db_subnet_group" "main" {
  name       = "${var.env}-db-subnet-group"
  subnet_ids = var.private_subnet_ids
  tags       = { Name = "${var.env}-db-subnet-group" }
}

# RDS PostgreSQL instance — private-only, no public endpoint
resource "aws_db_instance" "main" {
  identifier        = "${var.env}-postgres"
  engine            = "postgres"
  engine_version    = "16.3"
  instance_class    = var.db_instance_class
  allocated_storage = 20

  db_name  = "gocrud"
  username = "gocrud_admin"
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.sg_rds_id]

  # Prevents the instance from being reachable from outside the VPC
  publicly_accessible = false

  multi_az                = var.multi_az
  skip_final_snapshot     = var.skip_final_snapshot
  deletion_protection     = var.deletion_protection
  backup_retention_period = var.backup_retention_days

  tags = { Name = "${var.env}-postgres" }
}

# Cache subnet group — tells ElastiCache which subnets it is allowed to use
resource "aws_elasticache_subnet_group" "main" {
  name       = "${var.env}-cache-subnet-group"
  subnet_ids = var.private_subnet_ids
}

# ElastiCache Redis cluster — private-only, used by the Go app for caching
resource "aws_elasticache_cluster" "main" {
  cluster_id           = "${var.env}-redis"
  engine               = "redis"
  node_type            = var.redis_node_type
  num_cache_nodes      = var.redis_num_nodes
  parameter_group_name = "default.redis7"
  engine_version       = "7.1"
  port                 = 6379
  subnet_group_name    = aws_elasticache_subnet_group.main.name
  security_group_ids   = [var.sg_elasticache_id]
  tags                 = { Name = "${var.env}-redis" }
}
