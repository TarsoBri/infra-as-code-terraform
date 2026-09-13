output "alb_dns_name" {
  description = "Send HTTP requests to this URL to reach the Go API"
  value       = module.compute.alb_dns_name
}

output "ecr_repository_url" {
  description = "Push Docker images here; set this as ECR_REPOSITORY in GitHub secrets"
  value       = module.compute.ecr_repository_url
}

output "cloudfront_domain" {
  description = "CloudFront domain for serving static assets"
  value       = module.delivery.cloudfront_domain
}

output "github_actions_role_arn" {
  description = "Set this as AWS_DEPLOY_ROLE_ARN in GitHub repository secrets"
  value       = module.security.github_actions_role_arn
}

output "ecs_cluster_name" {
  description = "Set this as ECS_CLUSTER_NAME in GitHub repository secrets"
  value       = module.compute.ecs_cluster_name
}

output "ecs_service_name" {
  description = "Set this as ECS_SERVICE_NAME in GitHub repository secrets"
  value       = module.compute.ecs_service_name
}
