# ECS Execution Role — assumed by the ECS control plane (not the app) to pull images from ECR
# and inject secrets from Secrets Manager/SSM before the container starts
resource "aws_iam_role" "ecs_execution" {
  name = "${var.env}-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# AWS managed policy that grants the execution role permission to pull from ECR and write to CloudWatch Logs
resource "aws_iam_role_policy_attachment" "ecs_execution_managed" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Inline policy granting the execution role access to our specific secrets and SSM params
resource "aws_iam_role_policy" "ecs_execution_secrets" {
  name = "${var.env}-ecs-execution-secrets"
  role = aws_iam_role.ecs_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = ["arn:aws:secretsmanager:*:*:secret:/go-crud/${var.env}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["ssm:GetParameter", "ssm:GetParameters"]
        Resource = ["arn:aws:ssm:*:*:parameter/go-crud/${var.env}/*"]
      },
      {
        # KMS decrypt needed when SSM SecureString uses the default AWS-managed key
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = ["*"]
      }
    ]
  })
}

# ECS Task Role — assumed by the running Go container to call AWS APIs (S3 write, SSM read)
resource "aws_iam_role" "ecs_task" {
  name = "${var.env}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Least-privilege policy for the Go app: S3 read/write for assets, SSM read for config
resource "aws_iam_role_policy" "ecs_task_policy" {
  name = "${var.env}-ecs-task-policy"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"]
        Resource = ["${var.s3_bucket_arn}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["ssm:GetParameter"]
        Resource = ["arn:aws:ssm:*:*:parameter/go-crud/${var.env}/*"]
      }
    ]
  })
}

# Secrets Manager secret for the RDS master password
resource "aws_secretsmanager_secret" "db_password" {
  name = "/go-crud/${var.env}/db/password"
  # prod: 7-day recovery window before permanent deletion; dev: immediate deletion for clean teardown
  recovery_window_in_days = var.env == "prod" ? 7 : 0
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = var.db_password
}

# Secrets Manager secret for the RDS master username
resource "aws_secretsmanager_secret" "db_username" {
  name                    = "/go-crud/${var.env}/db/username"
  recovery_window_in_days = var.env == "prod" ? 7 : 0
}

resource "aws_secretsmanager_secret_version" "db_username" {
  secret_id     = aws_secretsmanager_secret.db_username.id
  secret_string = var.db_username
}

# SSM parameters store non-credential config values the app reads at startup
resource "aws_ssm_parameter" "app_port" {
  name  = "/go-crud/${var.env}/app/port"
  type  = "SecureString"
  value = "8080"
}

resource "aws_ssm_parameter" "log_level" {
  name  = "/go-crud/${var.env}/app/log_level"
  type  = "SecureString"
  value = var.env == "prod" ? "info" : "debug"
}

# Redis endpoint stored in SSM so ECS tasks can read it at runtime without hardcoding it
resource "aws_ssm_parameter" "redis_endpoint" {
  name  = "/go-crud/${var.env}/redis/endpoint"
  type  = "SecureString"
  value = var.redis_endpoint
}

# OIDC provider — trusts GitHub Actions tokens so our workflow can assume AWS roles
# without storing long-lived AWS access keys in GitHub secrets
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

# IAM role that GitHub Actions assumes during the deploy workflow
resource "aws_iam_role" "github_actions" {
  name = "${var.env}-github-actions-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/main"
        }
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

# Permissions for the GitHub Actions deploy role: ECR push + ECS service update
resource "aws_iam_role_policy" "github_actions_deploy" {
  name = "${var.env}-github-actions-deploy"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecs:UpdateService",
          "ecs:DescribeServices",
          "ecs:DescribeTaskDefinition",
          "ecs:RegisterTaskDefinition"
        ]
        Resource = "*"
      },
      {
        # Required to pass the task execution role when registering a new task definition
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = "*"
      }
    ]
  })
}
