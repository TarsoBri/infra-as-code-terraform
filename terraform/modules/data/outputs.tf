output "db_endpoint" {
  description = "RDS instance endpoint (host) for the Go app to connect to"
  value       = aws_db_instance.main.address
}

output "db_port" {
  description = "RDS port (5432 for PostgreSQL)"
  value       = aws_db_instance.main.port
}

output "redis_endpoint" {
  description = "ElastiCache Redis endpoint for the Go app to connect to"
  value       = aws_elasticache_cluster.main.cache_nodes[0].address
}

output "redis_port" {
  description = "ElastiCache Redis port (6379)"
  value       = aws_elasticache_cluster.main.port
}
