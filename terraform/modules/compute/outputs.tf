output "alb_dns_name" {
  description = "DNS name of the ALB — use this to send HTTP requests to the API"
  value       = aws_lb.main.dns_name
}

output "ecs_cluster_name" {
  description = "ECS cluster name — used by GitHub Actions to deploy new task definitions"
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "ECS service name — used by GitHub Actions to force new deployments"
  value       = aws_ecs_service.app.name
}

output "ecr_repository_url" {
  description = "ECR repository URL — used to tag and push Docker images"
  value       = aws_ecr_repository.app.repository_url
}
