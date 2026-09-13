output "ecs_execution_role_arn" {
  description = "ARN of the ECS execution role (used in task definition)"
  value       = aws_iam_role.ecs_execution.arn
}

output "ecs_task_role_arn" {
  description = "ARN of the ECS task role (assumed by the running Go container)"
  value       = aws_iam_role.ecs_task.arn
}

output "db_password_secret_arn" {
  description = "ARN of the Secrets Manager secret holding the DB password"
  value       = aws_secretsmanager_secret.db_password.arn
}

output "db_username_secret_arn" {
  description = "ARN of the Secrets Manager secret holding the DB username"
  value       = aws_secretsmanager_secret.db_username.arn
}

output "github_actions_role_arn" {
  description = "ARN of the IAM role assumed by GitHub Actions deploy workflow"
  value       = aws_iam_role.github_actions.arn
}
