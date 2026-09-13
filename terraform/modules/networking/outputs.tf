output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets (one per AZ)"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets (one per AZ)"
  value       = aws_subnet.private[*].id
}

output "sg_alb_id" {
  description = "Security group ID for the ALB"
  value       = aws_security_group.alb.id
}

output "sg_ecs_id" {
  description = "Security group ID for ECS tasks"
  value       = aws_security_group.ecs.id
}

output "sg_rds_id" {
  description = "Security group ID for RDS"
  value       = aws_security_group.rds.id
}

output "sg_elasticache_id" {
  description = "Security group ID for ElastiCache"
  value       = aws_security_group.elasticache.id
}
