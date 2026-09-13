# Terraform AWS IaC — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a production-grade AWS infrastructure for a Go CRUD API using Terraform, organized in layered modules with separate dev and prod environments, zero credentials in code, and a CI/CD pipeline via GitHub Actions.

**Architecture:** Layered modules (networking → security → data → compute → delivery) consumed by `environments/dev/` and `environments/prod/`. Each environment calls the same five modules with different variable values — sizing, AZ count, and protection flags differ; structure is identical.

**Tech Stack:** Terraform >= 1.5, AWS provider ~> 5.0, random provider ~> 3.0, Go 1.23, chi router, pgx/v5, go-redis/v9, GitHub Actions, Docker.

## Global Constraints

- All Terraform resource blocks must have a comment above them explaining what the resource does and why.
- No credentials, passwords, or sensitive values in any `.tf` file default or hardcoded string.
- `terraform.tfvars` files with real values are gitignored; only `.tfvars.example` is committed.
- Every module must have a `versions.tf` declaring `required_version = ">= 1.5.0"` and `required_providers`.
- All AWS resources must inherit tags via provider `default_tags` (Project, Environment, ManagedBy).
- Dev: 1 AZ, smallest instance sizes, deletion protection off, skip_final_snapshot true.
- Prod: 2 AZs, larger instances, deletion protection on, skip_final_snapshot false.
- Comments in Go code only when WHY is non-obvious.

---

## File Map

```
infra-as-code-terraform/
├── bootstrap/
│   ├── main.tf           # S3 bucket + DynamoDB table for remote state
│   ├── variables.tf
│   └── outputs.tf
├── modules/
│   ├── networking/
│   │   ├── versions.tf
│   │   ├── main.tf       # VPC, subnets, IGW, NAT GW, route tables, security groups
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── security/
│   │   ├── versions.tf
│   │   ├── main.tf       # IAM roles, Secrets Manager, SSM params, GitHub OIDC
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── data/
│   │   ├── versions.tf
│   │   ├── main.tf       # RDS PostgreSQL + ElastiCache Redis
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── compute/
│   │   ├── versions.tf
│   │   ├── main.tf       # ECR, ECS cluster, task def, service, ALB, auto scaling
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── delivery/
│       ├── versions.tf
│       ├── main.tf       # S3 bucket + CloudFront + OAC + bucket policy
│       ├── variables.tf
│       └── outputs.tf
├── environments/
│   ├── dev/
│   │   ├── backend.tf
│   │   ├── main.tf       # Calls all modules with dev values
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── terraform.tfvars.example
│   └── prod/
│       ├── backend.tf
│       ├── main.tf       # Calls all modules with prod values
│       ├── variables.tf
│       ├── outputs.tf
│       └── terraform.tfvars.example
├── app/
│   ├── main.go           # Server entry point, router setup, DB connection
│   ├── handlers.go       # HTTP handlers for all CRUD endpoints
│   ├── models.go         # Item struct, Repository interface, pgx implementation
│   ├── handlers_test.go  # Unit tests using mock repository
│   ├── go.mod
│   └── Dockerfile
├── .github/
│   └── workflows/
│       └── deploy.yml    # Build image → push ECR → update ECS task def → deploy
├── Makefile
├── .gitignore
└── README.md
```

---

### Task 1: Project Scaffold

**Files:**
- Create: `Makefile`
- Create: `.gitignore`
- Create: `README.md`

**Interfaces:**
- Produces: `make bootstrap`, `make dev-init`, `make dev-plan`, `make dev-up`, `make dev-down`, `make prod-init`, `make prod-plan`, `make prod-apply`

- [ ] **Step 1: Initialize git repository**

```bash
cd /path/to/infra-as-code-terraform
git init
```

- [ ] **Step 2: Create `.gitignore`**

```
# Terraform state and lock files — never commit these
*.tfstate
*.tfstate.backup
.terraform/
.terraform.lock.hcl

# Variable files with real secrets — commit only .tfvars.example
*.tfvars
!*.tfvars.example

# OS artifacts
.DS_Store
```

- [ ] **Step 3: Create `Makefile`**

```makefile
.PHONY: bootstrap dev-init dev-plan dev-up dev-down prod-init prod-plan prod-apply

# Run once to create S3 bucket and DynamoDB table for remote state
bootstrap:
	terraform -chdir=bootstrap init
	terraform -chdir=bootstrap apply -auto-approve

# --- Dev (auto-approve: safe to destroy and recreate freely) ---
dev-init:
	terraform -chdir=environments/dev init

dev-plan:
	terraform -chdir=environments/dev plan

dev-up:
	terraform -chdir=environments/dev apply -auto-approve

dev-down:
	terraform -chdir=environments/dev destroy -auto-approve

# --- Prod (no auto-approve: always requires manual confirmation) ---
prod-init:
	terraform -chdir=environments/prod init

prod-plan:
	terraform -chdir=environments/prod plan

prod-apply:
	terraform -chdir=environments/prod apply
```

- [ ] **Step 4: Create `README.md` with bootstrapping sequence**

```markdown
# infra-as-code-terraform

AWS infrastructure for a Go CRUD API. Terraform modules organized by layer.

## First-time setup

1. `make bootstrap` — creates S3 bucket + DynamoDB table for remote state (run once)
2. Copy `environments/dev/terraform.tfvars.example` to `environments/dev/terraform.tfvars` and fill values
3. `make dev-init` — initializes Terraform with the remote backend
4. `make dev-up` — provisions all dev infrastructure

## Daily workflow

| Command         | Effect                                      |
|-----------------|---------------------------------------------|
| `make dev-up`   | Spin up dev infrastructure                  |
| `make dev-down` | Tear down dev infrastructure (zero cost)    |
| `make dev-plan` | Preview changes before applying             |
| `make prod-plan`| Preview prod changes (never auto-approved)  |
| `make prod-apply`| Apply prod changes (requires confirmation) |

## Module dependency order

networking → security/data → compute → delivery
```

- [ ] **Step 5: Commit**

```bash
git add Makefile .gitignore README.md
git commit -m "chore: project scaffold, Makefile and .gitignore"
```

---

### Task 2: Bootstrap

**Files:**
- Create: `bootstrap/main.tf`
- Create: `bootstrap/variables.tf`
- Create: `bootstrap/outputs.tf`

**Interfaces:**
- Produces: S3 bucket `go-crud-terraform-state`, DynamoDB table `terraform-state-lock`
- Consumed by: `environments/dev/backend.tf`, `environments/prod/backend.tf`

- [ ] **Step 1: Create `bootstrap/variables.tf`**

```hcl
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
```

- [ ] **Step 2: Create `bootstrap/main.tf`**

```hcl
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# S3 bucket that stores all Terraform state files, one per environment
resource "aws_s3_bucket" "state" {
  bucket = "${var.project}-terraform-state"
}

# Enable versioning so we can recover previous state files if something goes wrong
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Encrypt all state files at rest with AES-256
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block all public access — state files contain sensitive infrastructure details
resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# DynamoDB table used by Terraform to lock state during apply, preventing concurrent runs
resource "aws_dynamodb_table" "state_lock" {
  name         = "terraform-state-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}
```

- [ ] **Step 3: Create `bootstrap/outputs.tf`**

```hcl
output "state_bucket_name" {
  description = "S3 bucket name to use in environment backend.tf files"
  value       = aws_s3_bucket.state.bucket
}

output "dynamodb_table_name" {
  description = "DynamoDB table name to use in environment backend.tf files"
  value       = aws_dynamodb_table.state_lock.name
}
```

- [ ] **Step 4: Validate bootstrap**

```bash
cd bootstrap
terraform init
terraform validate
terraform fmt -check
cd ..
```

Expected: `Success! The configuration is valid.`

- [ ] **Step 5: Commit**

```bash
git add bootstrap/
git commit -m "feat: bootstrap S3 + DynamoDB for remote state"
```

---

### Task 3: Module — Networking

**Files:**
- Create: `modules/networking/versions.tf`
- Create: `modules/networking/main.tf`
- Create: `modules/networking/variables.tf`
- Create: `modules/networking/outputs.tf`

**Interfaces:**
- Produces: `vpc_id` (string), `public_subnet_ids` (list(string)), `private_subnet_ids` (list(string)), `sg_alb_id` (string), `sg_ecs_id` (string), `sg_rds_id` (string), `sg_elasticache_id` (string)
- Consumed by: modules/data, modules/compute, environments/dev, environments/prod

- [ ] **Step 1: Create `modules/networking/versions.tf`**

```hcl
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
```

- [ ] **Step 2: Create `modules/networking/variables.tf`**

```hcl
variable "env" {
  description = "Environment name (dev or prod) used in resource names and tags"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of availability zones (1 for dev, 2 for prod)"
  type        = number
}

variable "public_subnet_cidrs" {
  description = "List of CIDR blocks for public subnets, one entry per AZ"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "List of CIDR blocks for private subnets, one entry per AZ"
  type        = list(string)
}
```

- [ ] **Step 3: Create `modules/networking/main.tf`**

```hcl
# Fetch available AZs in the current region dynamically
data "aws_availability_zones" "available" {
  state = "available"
}

# Main VPC — the network boundary for all resources
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = { Name = "${var.env}-vpc" }
}

# Public subnets — only the ALB lives here; exposed to the internet
resource "aws_subnet" "public" {
  count                   = var.az_count
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.env}-public-${count.index + 1}" }
}

# Private subnets — ECS tasks, RDS, and ElastiCache live here; no direct internet access
resource "aws_subnet" "private" {
  count             = var.az_count
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags              = { Name = "${var.env}-private-${count.index + 1}" }
}

# Internet Gateway — allows traffic to flow between the VPC and the internet
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.env}-igw" }
}

# Elastic IP for each NAT Gateway — static public IP required by AWS for NAT
resource "aws_eip" "nat" {
  count  = var.az_count
  domain = "vpc"
  tags   = { Name = "${var.env}-nat-eip-${count.index + 1}" }
}

# NAT Gateway — lets private subnet resources reach the internet (e.g., ECR pulls) without being reachable from it
resource "aws_nat_gateway" "main" {
  count         = var.az_count
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  tags          = { Name = "${var.env}-nat-${count.index + 1}" }
  depends_on    = [aws_internet_gateway.main]
}

# Route table for public subnets — routes all traffic to the Internet Gateway
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = { Name = "${var.env}-public-rt" }
}

# Associates each public subnet with the public route table
resource "aws_route_table_association" "public" {
  count          = var.az_count
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Route table per private subnet — each routes to its own NAT Gateway
resource "aws_route_table" "private" {
  count  = var.az_count
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }
  tags = { Name = "${var.env}-private-rt-${count.index + 1}" }
}

# Associates each private subnet with its corresponding route table
resource "aws_route_table_association" "private" {
  count          = var.az_count
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# Security group for the ALB — accepts HTTP and HTTPS from anywhere on the internet
resource "aws_security_group" "alb" {
  name   = "${var.env}-alb-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.env}-alb-sg" }
}

# Security group for ECS tasks — accepts traffic only from the ALB, not the open internet
resource "aws_security_group" "ecs" {
  name   = "${var.env}-ecs-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    description     = "All traffic from ALB only"
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.env}-ecs-sg" }
}

# Security group for RDS — accepts PostgreSQL only from ECS tasks
resource "aws_security_group" "rds" {
  name   = "${var.env}-rds-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from ECS tasks only"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.env}-rds-sg" }
}

# Security group for ElastiCache — accepts Redis only from ECS tasks
resource "aws_security_group" "elasticache" {
  name   = "${var.env}-elasticache-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    description     = "Redis from ECS tasks only"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.env}-elasticache-sg" }
}
```

- [ ] **Step 4: Create `modules/networking/outputs.tf`**

```hcl
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
```

- [ ] **Step 5: Validate module**

```bash
cd modules/networking
terraform init -backend=false
terraform validate
terraform fmt -check
cd ../..
```

Expected: `Success! The configuration is valid.`

- [ ] **Step 6: Commit**

```bash
git add modules/networking/
git commit -m "feat: networking module — VPC, subnets, NAT GW, security groups"
```

---

### Task 4: Module — Security

**Files:**
- Create: `modules/security/versions.tf`
- Create: `modules/security/main.tf`
- Create: `modules/security/variables.tf`
- Create: `modules/security/outputs.tf`

**Interfaces:**
- Consumes: `var.env`, `var.db_password` (sensitive), `var.db_username` (sensitive), `var.s3_bucket_arn`, `var.redis_endpoint`, `var.github_org`, `var.github_repo`
- Produces: `ecs_execution_role_arn` (string), `ecs_task_role_arn` (string), `db_password_secret_arn` (string), `db_username_secret_arn` (string), `github_actions_role_arn` (string)

- [ ] **Step 1: Create `modules/security/versions.tf`**

```hcl
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
```

- [ ] **Step 2: Create `modules/security/variables.tf`**

```hcl
variable "env" {
  description = "Environment name (dev or prod)"
  type        = string
}

variable "db_password" {
  description = "RDS master password — stored in Secrets Manager, never logged"
  type        = string
  sensitive   = true
}

variable "db_username" {
  description = "RDS master username — stored in Secrets Manager"
  type        = string
  sensitive   = true
}

variable "s3_bucket_arn" {
  description = "ARN of the S3 assets bucket — used to grant ECS task write access"
  type        = string
}

variable "redis_endpoint" {
  description = "ElastiCache Redis endpoint — stored in SSM for the app to read at startup"
  type        = string
}

variable "github_org" {
  description = "GitHub organization or user that owns the repository"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name (without the org prefix)"
  type        = string
}
```

- [ ] **Step 3: Create `modules/security/main.tf`**

```hcl
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
```

- [ ] **Step 4: Create `modules/security/outputs.tf`**

```hcl
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
```

- [ ] **Step 5: Validate module**

```bash
cd modules/security
terraform init -backend=false
terraform validate
terraform fmt -check
cd ../..
```

- [ ] **Step 6: Commit**

```bash
git add modules/security/
git commit -m "feat: security module — IAM roles, Secrets Manager, SSM, GitHub OIDC"
```

---

### Task 5: Module — Data

**Files:**
- Create: `modules/data/versions.tf`
- Create: `modules/data/main.tf`
- Create: `modules/data/variables.tf`
- Create: `modules/data/outputs.tf`

**Interfaces:**
- Consumes: `var.env`, `var.private_subnet_ids` (list(string)), `var.sg_rds_id` (string), `var.sg_elasticache_id` (string), `var.db_password` (string, sensitive), `var.db_instance_class` (string), `var.multi_az` (bool), `var.backup_retention_days` (number), `var.skip_final_snapshot` (bool), `var.deletion_protection` (bool), `var.redis_node_type` (string), `var.redis_num_nodes` (number)
- Produces: `db_endpoint` (string), `db_port` (number), `redis_endpoint` (string), `redis_port` (number)

- [ ] **Step 1: Create `modules/data/versions.tf`**

```hcl
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
```

- [ ] **Step 2: Create `modules/data/variables.tf`**

```hcl
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
```

- [ ] **Step 3: Create `modules/data/main.tf`**

```hcl
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
```

- [ ] **Step 4: Create `modules/data/outputs.tf`**

```hcl
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
```

- [ ] **Step 5: Validate module**

```bash
cd modules/data
terraform init -backend=false
terraform validate
terraform fmt -check
cd ../..
```

- [ ] **Step 6: Commit**

```bash
git add modules/data/
git commit -m "feat: data module — RDS PostgreSQL and ElastiCache Redis"
```

---

### Task 6: Module — Compute

**Files:**
- Create: `modules/compute/versions.tf`
- Create: `modules/compute/main.tf`
- Create: `modules/compute/variables.tf`
- Create: `modules/compute/outputs.tf`

**Interfaces:**
- Consumes: `var.env`, `var.vpc_id`, `var.public_subnet_ids`, `var.private_subnet_ids`, `var.sg_alb_id`, `var.sg_ecs_id`, `var.ecs_execution_role_arn`, `var.ecs_task_role_arn`, `var.container_image`, `var.task_cpu`, `var.task_memory`, `var.min_tasks`, `var.max_tasks`, `var.db_password_secret_arn`, `var.db_username_secret_arn`, `var.db_endpoint`, `var.redis_endpoint`, `var.aws_region`
- Produces: `alb_dns_name` (string), `ecs_cluster_name` (string), `ecs_service_name` (string), `ecr_repository_url` (string)

- [ ] **Step 1: Create `modules/compute/versions.tf`**

```hcl
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
```

- [ ] **Step 2: Create `modules/compute/variables.tf`**

```hcl
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
```

- [ ] **Step 3: Create `modules/compute/main.tf`**

```hcl
# ECR repository — stores Docker images for the Go API, tagged by commit SHA
resource "aws_ecr_repository" "app" {
  name                 = "go-crud-${var.env}"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# Lifecycle policy — keeps only the last 10 images to control storage costs
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}

# ECS cluster — logical grouping for all Fargate tasks in this environment
resource "aws_ecs_cluster" "main" {
  name = "${var.env}-cluster"
}

# CloudWatch log group — collects stdout/stderr from all Go API containers
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.env}/go-crud"
  retention_in_days = 7
}

# ECS task definition — blueprint for each container: CPU, memory, image, secrets, and log config
resource "aws_ecs_task_definition" "app" {
  family                   = "${var.env}-go-crud"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = var.ecs_execution_role_arn
  task_role_arn            = var.ecs_task_role_arn

  container_definitions = jsonencode([{
    name  = "go-crud"
    image = var.container_image

    portMappings = [{
      containerPort = 8080
      protocol      = "tcp"
    }]

    # Secrets fetched from Secrets Manager by the execution role before the container starts
    secrets = [
      { name = "DB_PASSWORD", valueFrom = var.db_password_secret_arn },
      { name = "DB_USERNAME", valueFrom = var.db_username_secret_arn }
    ]

    # Non-sensitive config values passed as plain environment variables
    environment = [
      { name = "APP_PORT", value = "8080" },
      { name = "ENV", value = var.env },
      { name = "DB_HOST", value = var.db_endpoint },
      { name = "DB_PORT", value = "5432" },
      { name = "DB_NAME", value = "gocrud" },
      { name = "REDIS_ADDR", value = "${var.redis_endpoint}:6379" }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = "/ecs/${var.env}/go-crud"
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "go-crud"
      }
    }

    # ALB uses this health check to decide if the task is ready to receive traffic
    healthCheck = {
      command     = ["CMD-SHELL", "curl -f http://localhost:8080/health || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 60
    }
  }])
}

# ALB — internet-facing load balancer in public subnets that routes traffic to ECS
resource "aws_lb" "main" {
  name               = "${var.env}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.sg_alb_id]
  subnets            = var.public_subnet_ids
}

# Target group — the ALB sends requests here; ECS registers tasks as targets automatically
resource "aws_lb_target_group" "app" {
  name        = "${var.env}-go-crud-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
  }
}

# ALB listener — accepts HTTP on port 80 and forwards requests to the target group
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# ECS service — keeps min_tasks running at all times and registers them with the ALB
resource "aws_ecs_service" "app" {
  name            = "${var.env}-go-crud"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.min_tasks
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.sg_ecs_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "go-crud"
    container_port   = 8080
  }

  # Listener must exist before the service starts registering targets
  depends_on = [aws_lb_listener.http]
}

# Auto Scaling target — registers this ECS service as a scalable resource
resource "aws_appautoscaling_target" "app" {
  max_capacity       = var.max_tasks
  min_capacity       = var.min_tasks
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.app.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# Auto Scaling policy — adds tasks when average CPU exceeds 60%, removes them when it drops
resource "aws_appautoscaling_policy" "cpu" {
  name               = "${var.env}-cpu-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.app.resource_id
  scalable_dimension = aws_appautoscaling_target.app.scalable_dimension
  service_namespace  = aws_appautoscaling_target.app.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value = 60.0
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}
```

- [ ] **Step 4: Create `modules/compute/outputs.tf`**

```hcl
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
```

- [ ] **Step 5: Validate module**

```bash
cd modules/compute
terraform init -backend=false
terraform validate
terraform fmt -check
cd ../..
```

- [ ] **Step 6: Commit**

```bash
git add modules/compute/
git commit -m "feat: compute module — ECR, ECS, ALB, Auto Scaling"
```

---

### Task 7: Module — Delivery

**Files:**
- Create: `modules/delivery/versions.tf`
- Create: `modules/delivery/main.tf`
- Create: `modules/delivery/variables.tf`
- Create: `modules/delivery/outputs.tf`

**Interfaces:**
- Consumes: `var.env`, `var.bucket_name` (string), `var.versioning_enabled` (bool), `var.price_class` (string)
- Produces: `cloudfront_domain` (string), `s3_bucket_name` (string), `s3_bucket_arn` (string)

- [ ] **Step 1: Create `modules/delivery/versions.tf`**

```hcl
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
```

- [ ] **Step 2: Create `modules/delivery/variables.tf`**

```hcl
variable "env" {
  description = "Environment name (dev or prod)"
  type        = string
}

variable "bucket_name" {
  description = "Globally unique S3 bucket name for assets"
  type        = string
}

variable "versioning_enabled" {
  description = "Enable S3 object versioning — false in dev, true in prod"
  type        = bool
}

variable "price_class" {
  description = "CloudFront price class — PriceClass_100 for dev (cheaper), PriceClass_All for prod"
  type        = string
  default     = "PriceClass_100"
}
```

- [ ] **Step 3: Create `modules/delivery/main.tf`**

```hcl
# S3 bucket for static assets — kept private, CloudFront is the only allowed reader
resource "aws_s3_bucket" "main" {
  bucket = var.bucket_name
}

# Block all public access — OAC ensures only CloudFront can reach this bucket
resource "aws_s3_bucket_public_access_block" "main" {
  bucket                  = aws_s3_bucket.main.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Object versioning — enabled in prod so we can roll back overwritten assets
resource "aws_s3_bucket_versioning" "main" {
  bucket = aws_s3_bucket.main.id
  versioning_configuration {
    status = var.versioning_enabled ? "Enabled" : "Suspended"
  }
}

# Origin Access Control — CloudFront uses this identity to sign requests to S3
resource "aws_cloudfront_origin_access_control" "main" {
  name                              = "${var.env}-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# CloudFront distribution — CDN that terminates HTTPS and serves assets from S3
resource "aws_cloudfront_distribution" "main" {
  enabled = true
  comment = "${var.env} assets distribution"

  origin {
    domain_name              = aws_s3_bucket.main.bucket_regional_domain_name
    origin_id                = "s3-${var.bucket_name}"
    origin_access_control_id = aws_cloudfront_origin_access_control.main.id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "s3-${var.bucket_name}"
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }
  }

  price_class = var.price_class

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# Bucket policy — grants CloudFront (via OAC) the only read access to S3 objects
resource "aws_s3_bucket_policy" "main" {
  bucket = aws_s3_bucket.main.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowCloudFrontServicePrincipal"
      Effect = "Allow"
      Principal = {
        Service = "cloudfront.amazonaws.com"
      }
      Action   = "s3:GetObject"
      Resource = "${aws_s3_bucket.main.arn}/*"
      Condition = {
        StringEquals = {
          "AWS:SourceArn" = aws_cloudfront_distribution.main.arn
        }
      }
    }]
  })
}
```

- [ ] **Step 4: Create `modules/delivery/outputs.tf`**

```hcl
output "cloudfront_domain" {
  description = "CloudFront distribution domain name for serving assets"
  value       = aws_cloudfront_distribution.main.domain_name
}

output "s3_bucket_name" {
  description = "S3 bucket name for uploading assets"
  value       = aws_s3_bucket.main.bucket
}

output "s3_bucket_arn" {
  description = "S3 bucket ARN — passed to security module to grant ECS task write access"
  value       = aws_s3_bucket.main.arn
}
```

- [ ] **Step 5: Validate module**

```bash
cd modules/delivery
terraform init -backend=false
terraform validate
terraform fmt -check
cd ../..
```

- [ ] **Step 6: Commit**

```bash
git add modules/delivery/
git commit -m "feat: delivery module — S3 and CloudFront with OAC"
```

---

### Task 8: Environment — Dev

**Files:**
- Create: `environments/dev/backend.tf`
- Create: `environments/dev/main.tf`
- Create: `environments/dev/variables.tf`
- Create: `environments/dev/outputs.tf`
- Create: `environments/dev/terraform.tfvars.example`

**Interfaces:**
- Consumes: all five modules' outputs via module calls
- Produces: `alb_dns_name`, `ecr_repository_url`, `cloudfront_domain`, `github_actions_role_arn`

- [ ] **Step 1: Create `environments/dev/backend.tf`**

```hcl
terraform {
  backend "s3" {
    bucket         = "go-crud-terraform-state"
    key            = "dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}
```

- [ ] **Step 2: Create `environments/dev/variables.tf`**

```hcl
variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "db_password" {
  description = "RDS master password — provide via terraform.tfvars, never hardcode"
  type        = string
  sensitive   = true
}

variable "db_username" {
  description = "RDS master username — provide via terraform.tfvars"
  type        = string
  sensitive   = true
}

variable "github_org" {
  description = "GitHub organization or user that owns this repository"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name (without the org prefix)"
  type        = string
}
```

- [ ] **Step 3: Create `environments/dev/main.tf`**

```hcl
provider "aws" {
  region = var.aws_region

  # Applied to every resource created in this environment
  default_tags {
    tags = {
      Project     = "go-crud"
      Environment = "dev"
      ManagedBy   = "terraform"
    }
  }
}

# Networking is always created first — all other modules depend on its outputs
module "networking" {
  source = "../../modules/networking"

  env                  = "dev"
  vpc_cidr             = "10.0.0.0/16"
  az_count             = 1
  public_subnet_cidrs  = ["10.0.1.0/24"]
  private_subnet_cidrs = ["10.0.10.0/24"]
}

# Delivery is independent of networking — create early so its S3 ARN is available for security
module "delivery" {
  source = "../../modules/delivery"

  env                = "dev"
  bucket_name        = "go-crud-dev-assets"
  versioning_enabled = false
  price_class        = "PriceClass_100"
}

# Data must exist before security so redis_endpoint is available for the SSM parameter
module "data" {
  source = "../../modules/data"

  env                   = "dev"
  private_subnet_ids    = module.networking.private_subnet_ids
  sg_rds_id             = module.networking.sg_rds_id
  sg_elasticache_id     = module.networking.sg_elasticache_id
  db_password           = var.db_password
  db_instance_class     = "db.t3.micro"
  multi_az              = false
  backup_retention_days = 1
  skip_final_snapshot   = true
  deletion_protection   = false
  redis_node_type       = "cache.t3.micro"
  redis_num_nodes       = 1
}

# Security creates IAM roles and stores secrets — depends on delivery (S3 ARN) and data (redis endpoint)
module "security" {
  source = "../../modules/security"

  env            = "dev"
  db_password    = var.db_password
  db_username    = var.db_username
  s3_bucket_arn  = module.delivery.s3_bucket_arn
  redis_endpoint = module.data.redis_endpoint
  github_org     = var.github_org
  github_repo    = var.github_repo
}

# Compute is last — depends on networking, security (IAM ARNs), and data (DB/Redis endpoints)
module "compute" {
  source = "../../modules/compute"

  env                    = "dev"
  vpc_id                 = module.networking.vpc_id
  public_subnet_ids      = module.networking.public_subnet_ids
  private_subnet_ids     = module.networking.private_subnet_ids
  sg_alb_id              = module.networking.sg_alb_id
  sg_ecs_id              = module.networking.sg_ecs_id
  ecs_execution_role_arn = module.security.ecs_execution_role_arn
  ecs_task_role_arn      = module.security.ecs_task_role_arn
  # Use nginx as a placeholder until the first CI/CD run pushes the Go image
  container_image        = "nginx:1.27"
  task_cpu               = 256
  task_memory            = 512
  min_tasks              = 1
  max_tasks              = 2
  db_password_secret_arn = module.security.db_password_secret_arn
  db_username_secret_arn = module.security.db_username_secret_arn
  db_endpoint            = module.data.db_endpoint
  redis_endpoint         = module.data.redis_endpoint
  aws_region             = var.aws_region
}
```

- [ ] **Step 4: Create `environments/dev/outputs.tf`**

```hcl
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
```

- [ ] **Step 5: Create `environments/dev/terraform.tfvars.example`**

```hcl
aws_region  = "us-east-1"
db_password = "REPLACE_WITH_STRONG_PASSWORD"
db_username = "gocrud_admin"
github_org  = "REPLACE_WITH_YOUR_GITHUB_ORG_OR_USER"
github_repo = "infra-as-code-terraform"
```

- [ ] **Step 6: Validate environment**

```bash
# Copy example to actual (only for local validation, never commit the real file)
cp environments/dev/terraform.tfvars.example environments/dev/terraform.tfvars
# Edit terraform.tfvars with real values before running
cd environments/dev
terraform init
terraform validate
terraform fmt -check
cd ../..
```

- [ ] **Step 7: Commit**

```bash
git add environments/dev/
git commit -m "feat: dev environment — wires all modules with dev-sized variables"
```

---

### Task 9: Environment — Prod

**Files:**
- Create: `environments/prod/backend.tf`
- Create: `environments/prod/main.tf`
- Create: `environments/prod/variables.tf`
- Create: `environments/prod/outputs.tf`
- Create: `environments/prod/terraform.tfvars.example`

**Interfaces:**
- Consumes: all five modules (same as dev but with prod-sized variables)
- Produces: same outputs as dev environment

- [ ] **Step 1: Create `environments/prod/backend.tf`**

```hcl
terraform {
  backend "s3" {
    bucket         = "go-crud-terraform-state"
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}
```

- [ ] **Step 2: Create `environments/prod/variables.tf`**

```hcl
variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "db_password" {
  description = "RDS master password — provide via terraform.tfvars, never hardcode"
  type        = string
  sensitive   = true
}

variable "db_username" {
  description = "RDS master username — provide via terraform.tfvars"
  type        = string
  sensitive   = true
}

variable "github_org" {
  description = "GitHub organization or user that owns this repository"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name (without the org prefix)"
  type        = string
}
```

- [ ] **Step 3: Create `environments/prod/main.tf`**

```hcl
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "go-crud"
      Environment = "prod"
      ManagedBy   = "terraform"
    }
  }
}

module "networking" {
  source = "../../modules/networking"

  env                  = "prod"
  vpc_cidr             = "10.1.0.0/16"
  az_count             = 2
  public_subnet_cidrs  = ["10.1.1.0/24", "10.1.2.0/24"]
  private_subnet_cidrs = ["10.1.10.0/24", "10.1.11.0/24"]
}

module "delivery" {
  source = "../../modules/delivery"

  env                = "prod"
  bucket_name        = "go-crud-prod-assets"
  versioning_enabled = true
  price_class        = "PriceClass_All"
}

module "data" {
  source = "../../modules/data"

  env                   = "prod"
  private_subnet_ids    = module.networking.private_subnet_ids
  sg_rds_id             = module.networking.sg_rds_id
  sg_elasticache_id     = module.networking.sg_elasticache_id
  db_password           = var.db_password
  db_instance_class     = "db.t3.small"
  multi_az              = true
  backup_retention_days = 7
  skip_final_snapshot   = false
  deletion_protection   = true
  redis_node_type       = "cache.t3.small"
  redis_num_nodes       = 2
}

module "security" {
  source = "../../modules/security"

  env            = "prod"
  db_password    = var.db_password
  db_username    = var.db_username
  s3_bucket_arn  = module.delivery.s3_bucket_arn
  redis_endpoint = module.data.redis_endpoint
  github_org     = var.github_org
  github_repo    = var.github_repo
}

module "compute" {
  source = "../../modules/compute"

  env                    = "prod"
  vpc_id                 = module.networking.vpc_id
  public_subnet_ids      = module.networking.public_subnet_ids
  private_subnet_ids     = module.networking.private_subnet_ids
  sg_alb_id              = module.networking.sg_alb_id
  sg_ecs_id              = module.networking.sg_ecs_id
  ecs_execution_role_arn = module.security.ecs_execution_role_arn
  ecs_task_role_arn      = module.security.ecs_task_role_arn
  container_image        = "nginx:1.27"
  task_cpu               = 512
  task_memory            = 1024
  min_tasks              = 2
  max_tasks              = 6
  db_password_secret_arn = module.security.db_password_secret_arn
  db_username_secret_arn = module.security.db_username_secret_arn
  db_endpoint            = module.data.db_endpoint
  redis_endpoint         = module.data.redis_endpoint
  aws_region             = var.aws_region
}
```

- [ ] **Step 4: Create `environments/prod/outputs.tf`** (identical structure to dev)

```hcl
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
```

- [ ] **Step 5: Create `environments/prod/terraform.tfvars.example`**

```hcl
aws_region  = "us-east-1"
db_password = "REPLACE_WITH_STRONG_PASSWORD"
db_username = "gocrud_admin"
github_org  = "REPLACE_WITH_YOUR_GITHUB_ORG_OR_USER"
github_repo = "infra-as-code-terraform"
```

- [ ] **Step 6: Validate environment**

```bash
cd environments/prod
terraform validate
terraform fmt -check
cd ../..
```

- [ ] **Step 7: Commit**

```bash
git add environments/prod/
git commit -m "feat: prod environment — 2 AZs, Multi-AZ RDS, larger instances"
```

---

### Task 10: Go CRUD API

**Files:**
- Create: `app/go.mod`
- Create: `app/models.go`
- Create: `app/handlers.go`
- Create: `app/main.go`
- Create: `app/handlers_test.go`
- Create: `app/Dockerfile`

**Interfaces:**
- Consumes env vars: `APP_PORT`, `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USERNAME` (from Secrets Manager), `DB_PASSWORD` (from Secrets Manager), `REDIS_ADDR`
- Produces HTTP endpoints: `GET /health`, `POST /items`, `GET /items`, `GET /items/{id}`, `PUT /items/{id}`, `DELETE /items/{id}`

- [ ] **Step 1: Create `app/go.mod`**

```bash
cd app
go mod init github.com/your-org/go-crud
go get github.com/go-chi/chi/v5
go get github.com/jackc/pgx/v5/pgxpool
go get github.com/redis/go-redis/v9
cd ..
```

- [ ] **Step 2: Write failing tests in `app/handlers_test.go`**

```go
package main

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/go-chi/chi/v5"
)

// mockRepo is an in-memory implementation of Repository used only in tests
type mockRepo struct {
	items  map[int]Item
	nextID int
}

func newMockRepo() *mockRepo {
	return &mockRepo{items: make(map[int]Item), nextID: 1}
}

func (m *mockRepo) Create(ctx context.Context, req CreateItemRequest) (Item, error) {
	item := Item{ID: m.nextID, Name: req.Name, Description: req.Description}
	m.items[m.nextID] = item
	m.nextID++
	return item, nil
}

func (m *mockRepo) List(ctx context.Context) ([]Item, error) {
	result := make([]Item, 0, len(m.items))
	for _, item := range m.items {
		result = append(result, item)
	}
	return result, nil
}

func (m *mockRepo) GetByID(ctx context.Context, id int) (Item, error) {
	item, ok := m.items[id]
	if !ok {
		return Item{}, ErrNotFound
	}
	return item, nil
}

func (m *mockRepo) Update(ctx context.Context, id int, req CreateItemRequest) (Item, error) {
	if _, ok := m.items[id]; !ok {
		return Item{}, ErrNotFound
	}
	item := Item{ID: id, Name: req.Name, Description: req.Description}
	m.items[id] = item
	return item, nil
}

func (m *mockRepo) Delete(ctx context.Context, id int) error {
	if _, ok := m.items[id]; !ok {
		return ErrNotFound
	}
	delete(m.items, id)
	return nil
}

func newTestRouter(repo Repository) http.Handler {
	h := &handler{repo: repo}
	r := chi.NewRouter()
	r.Get("/health", h.health)
	r.Post("/items", h.create)
	r.Get("/items", h.list)
	r.Get("/items/{id}", h.get)
	r.Put("/items/{id}", h.update)
	r.Delete("/items/{id}", h.delete)
	return r
}

func TestHealth(t *testing.T) {
	r := newTestRouter(newMockRepo())
	w := httptest.NewRecorder()
	r.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/health", nil))
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}
}

func TestCreateAndGetItem(t *testing.T) {
	r := newTestRouter(newMockRepo())

	body, _ := json.Marshal(CreateItemRequest{Name: "book", Description: "a novel"})
	w := httptest.NewRecorder()
	r.ServeHTTP(w, httptest.NewRequest(http.MethodPost, "/items", bytes.NewReader(body)))
	if w.Code != http.StatusCreated {
		t.Fatalf("create: expected 201, got %d", w.Code)
	}

	var created Item
	json.NewDecoder(w.Body).Decode(&created)
	if created.Name != "book" {
		t.Fatalf("expected name 'book', got %q", created.Name)
	}

	w2 := httptest.NewRecorder()
	r.ServeHTTP(w2, httptest.NewRequest(http.MethodGet, "/items/1", nil))
	if w2.Code != http.StatusOK {
		t.Fatalf("get: expected 200, got %d", w2.Code)
	}
}

func TestListItems(t *testing.T) {
	repo := newMockRepo()
	repo.Create(context.Background(), CreateItemRequest{Name: "a"})
	repo.Create(context.Background(), CreateItemRequest{Name: "b"})

	r := newTestRouter(repo)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/items", nil))
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}

	var items []Item
	json.NewDecoder(w.Body).Decode(&items)
	if len(items) != 2 {
		t.Fatalf("expected 2 items, got %d", len(items))
	}
}

func TestUpdateItem(t *testing.T) {
	repo := newMockRepo()
	repo.Create(context.Background(), CreateItemRequest{Name: "old"})

	r := newTestRouter(repo)
	body, _ := json.Marshal(CreateItemRequest{Name: "new"})
	w := httptest.NewRecorder()
	r.ServeHTTP(w, httptest.NewRequest(http.MethodPut, "/items/1", bytes.NewReader(body)))
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}

	var updated Item
	json.NewDecoder(w.Body).Decode(&updated)
	if updated.Name != "new" {
		t.Fatalf("expected name 'new', got %q", updated.Name)
	}
}

func TestDeleteItem(t *testing.T) {
	repo := newMockRepo()
	repo.Create(context.Background(), CreateItemRequest{Name: "to-delete"})

	r := newTestRouter(repo)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, httptest.NewRequest(http.MethodDelete, "/items/1", nil))
	if w.Code != http.StatusNoContent {
		t.Fatalf("expected 204, got %d", w.Code)
	}
}
```

- [ ] **Step 3: Run tests — expect compile failure**

```bash
cd app && go test ./... 2>&1; cd ..
```

Expected: compile error — `ErrNotFound`, `CreateItemRequest`, `Item`, `Repository`, `handler` not defined yet.

- [ ] **Step 4: Create `app/models.go`**

```go
package main

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

var ErrNotFound = errors.New("item not found")

type Item struct {
	ID          int       `json:"id"`
	Name        string    `json:"name"`
	Description string    `json:"description"`
	CreatedAt   time.Time `json:"created_at"`
}

type CreateItemRequest struct {
	Name        string `json:"name"`
	Description string `json:"description"`
}

type Repository interface {
	Create(ctx context.Context, req CreateItemRequest) (Item, error)
	List(ctx context.Context) ([]Item, error)
	GetByID(ctx context.Context, id int) (Item, error)
	Update(ctx context.Context, id int, req CreateItemRequest) (Item, error)
	Delete(ctx context.Context, id int) error
}

type pgRepository struct {
	pool *pgxpool.Pool
}

func newPgRepository(pool *pgxpool.Pool) Repository {
	return &pgRepository{pool: pool}
}

func (r *pgRepository) Create(ctx context.Context, req CreateItemRequest) (Item, error) {
	var item Item
	err := r.pool.QueryRow(ctx,
		`INSERT INTO items (name, description) VALUES ($1, $2) RETURNING id, name, description, created_at`,
		req.Name, req.Description,
	).Scan(&item.ID, &item.Name, &item.Description, &item.CreatedAt)
	return item, err
}

func (r *pgRepository) List(ctx context.Context) ([]Item, error) {
	rows, err := r.pool.Query(ctx, `SELECT id, name, description, created_at FROM items ORDER BY id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var items []Item
	for rows.Next() {
		var item Item
		if err := rows.Scan(&item.ID, &item.Name, &item.Description, &item.CreatedAt); err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	return items, rows.Err()
}

func (r *pgRepository) GetByID(ctx context.Context, id int) (Item, error) {
	var item Item
	err := r.pool.QueryRow(ctx,
		`SELECT id, name, description, created_at FROM items WHERE id = $1`, id,
	).Scan(&item.ID, &item.Name, &item.Description, &item.CreatedAt)
	if err != nil {
		return Item{}, fmt.Errorf("%w: id %d", ErrNotFound, id)
	}
	return item, nil
}

func (r *pgRepository) Update(ctx context.Context, id int, req CreateItemRequest) (Item, error) {
	var item Item
	err := r.pool.QueryRow(ctx,
		`UPDATE items SET name=$1, description=$2 WHERE id=$3 RETURNING id, name, description, created_at`,
		req.Name, req.Description, id,
	).Scan(&item.ID, &item.Name, &item.Description, &item.CreatedAt)
	if err != nil {
		return Item{}, fmt.Errorf("%w: id %d", ErrNotFound, id)
	}
	return item, nil
}

func (r *pgRepository) Delete(ctx context.Context, id int) error {
	result, err := r.pool.Exec(ctx, `DELETE FROM items WHERE id = $1`, id)
	if err != nil {
		return err
	}
	if result.RowsAffected() == 0 {
		return fmt.Errorf("%w: id %d", ErrNotFound, id)
	}
	return nil
}
```

- [ ] **Step 5: Create `app/handlers.go`**

```go
package main

import (
	"encoding/json"
	"errors"
	"net/http"
	"strconv"

	"github.com/go-chi/chi/v5"
)

type handler struct {
	repo Repository
}

func (h *handler) health(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}

func (h *handler) create(w http.ResponseWriter, r *http.Request) {
	var req CreateItemRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid request body", http.StatusBadRequest)
		return
	}

	item, err := h.repo.Create(r.Context(), req)
	if err != nil {
		http.Error(w, "internal error", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(item)
}

func (h *handler) list(w http.ResponseWriter, r *http.Request) {
	items, err := h.repo.List(r.Context())
	if err != nil {
		http.Error(w, "internal error", http.StatusInternalServerError)
		return
	}

	if items == nil {
		items = []Item{}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(items)
}

func (h *handler) get(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.Atoi(chi.URLParam(r, "id"))
	if err != nil {
		http.Error(w, "invalid id", http.StatusBadRequest)
		return
	}

	item, err := h.repo.GetByID(r.Context(), id)
	if errors.Is(err, ErrNotFound) {
		http.Error(w, "not found", http.StatusNotFound)
		return
	}
	if err != nil {
		http.Error(w, "internal error", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(item)
}

func (h *handler) update(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.Atoi(chi.URLParam(r, "id"))
	if err != nil {
		http.Error(w, "invalid id", http.StatusBadRequest)
		return
	}

	var req CreateItemRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid request body", http.StatusBadRequest)
		return
	}

	item, err := h.repo.Update(r.Context(), id, req)
	if errors.Is(err, ErrNotFound) {
		http.Error(w, "not found", http.StatusNotFound)
		return
	}
	if err != nil {
		http.Error(w, "internal error", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(item)
}

func (h *handler) delete(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.Atoi(chi.URLParam(r, "id"))
	if err != nil {
		http.Error(w, "invalid id", http.StatusBadRequest)
		return
	}

	if err := h.repo.Delete(r.Context(), id); errors.Is(err, ErrNotFound) {
		http.Error(w, "not found", http.StatusNotFound)
		return
	} else if err != nil {
		http.Error(w, "internal error", http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}
```

- [ ] **Step 6: Create `app/main.go`**

```go
package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

func main() {
	port := os.Getenv("APP_PORT")
	if port == "" {
		port = "8080"
	}

	pool, err := pgxpool.New(context.Background(), buildDSN())
	if err != nil {
		log.Fatalf("cannot connect to database: %v", err)
	}
	defer pool.Close()

	if _, err := pool.Exec(context.Background(), `
		CREATE TABLE IF NOT EXISTS items (
			id          SERIAL PRIMARY KEY,
			name        TEXT NOT NULL,
			description TEXT,
			created_at  TIMESTAMPTZ DEFAULT NOW()
		)
	`); err != nil {
		log.Fatalf("cannot create items table: %v", err)
	}

	h := &handler{repo: newPgRepository(pool)}
	r := chi.NewRouter()
	r.Get("/health", h.health)
	r.Post("/items", h.create)
	r.Get("/items", h.list)
	r.Get("/items/{id}", h.get)
	r.Put("/items/{id}", h.update)
	r.Delete("/items/{id}", h.delete)

	log.Printf("listening on :%s (env=%s)", port, os.Getenv("ENV"))
	log.Fatal(http.ListenAndServe(":"+port, r))
}

func buildDSN() string {
	return fmt.Sprintf(
		"postgres://%s:%s@%s:%s/%s?sslmode=require",
		os.Getenv("DB_USERNAME"),
		os.Getenv("DB_PASSWORD"),
		os.Getenv("DB_HOST"),
		os.Getenv("DB_PORT"),
		os.Getenv("DB_NAME"),
	)
}
```

- [ ] **Step 7: Run tests — expect all pass**

```bash
cd app && go test ./... -v; cd ..
```

Expected:
```
--- PASS: TestHealth
--- PASS: TestCreateAndGetItem
--- PASS: TestListItems
--- PASS: TestUpdateItem
--- PASS: TestDeleteItem
PASS
```

- [ ] **Step 8: Create `app/Dockerfile`**

```dockerfile
# Build stage — compile the Go binary in a full Go image
FROM golang:1.23-alpine AS builder

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o server .

# Runtime stage — minimal Alpine image, only the binary and curl for the ECS health check
FROM alpine:3.20
RUN apk add --no-cache ca-certificates curl

WORKDIR /app
COPY --from=builder /app/server .

EXPOSE 8080
CMD ["./server"]
```

- [ ] **Step 9: Commit**

```bash
git add app/
git commit -m "feat: Go CRUD API with pgx, chi router, and unit tests"
```

---

### Task 11: CI/CD — GitHub Actions

**Files:**
- Create: `.github/workflows/deploy.yml`

**Interfaces:**
- Consumes GitHub secrets: `AWS_DEPLOY_ROLE_ARN`, `ECR_REPOSITORY`, `ECS_CLUSTER_NAME`, `ECS_SERVICE_NAME`, `ECS_TASK_FAMILY`
- Triggers on: push to `main`
- Produces: new ECS task definition revision + forced deployment

- [ ] **Step 1: Create `.github/workflows/deploy.yml`**

```yaml
name: Build and Deploy to ECS

on:
  push:
    branches: [main]

# Required for OIDC — allows GitHub Actions to request an AWS token
permissions:
  id-token: write
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout source code
        uses: actions/checkout@v4

      # Assumes the IAM role created by the security module via OIDC — no AWS keys stored in GitHub
      - name: Configure AWS credentials via OIDC
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_DEPLOY_ROLE_ARN }}
          aws-region: us-east-1

      # Gets the ECR login token so docker can push to the private registry
      - name: Login to Amazon ECR
        id: login-ecr
        uses: aws-actions/amazon-ecr-login@v2

      # Builds the Go image and tags it with the commit SHA for traceability
      - name: Build and push Docker image to ECR
        id: build
        env:
          REGISTRY: ${{ steps.login-ecr.outputs.registry }}
          REPOSITORY: ${{ secrets.ECR_REPOSITORY }}
          IMAGE_TAG: ${{ github.sha }}
        run: |
          docker build -t $REGISTRY/$REPOSITORY:$IMAGE_TAG ./app
          docker push $REGISTRY/$REPOSITORY:$IMAGE_TAG
          echo "image=$REGISTRY/$REPOSITORY:$IMAGE_TAG" >> $GITHUB_OUTPUT

      # Downloads the current task definition so we can update just the image field
      - name: Download current ECS task definition
        run: |
          aws ecs describe-task-definition \
            --task-definition ${{ secrets.ECS_TASK_FAMILY }} \
            --query taskDefinition > task-definition.json

      # Renders a new task definition JSON with the updated container image
      - name: Update container image in task definition
        id: task-def
        uses: aws-actions/amazon-ecs-render-task-definition@v1
        with:
          task-definition: task-definition.json
          container-name: go-crud
          image: ${{ steps.build.outputs.image }}

      # Registers the new task definition and updates the ECS service — waits for stability
      - name: Deploy new task definition to ECS
        uses: aws-actions/amazon-ecs-deploy-task-definition@v1
        with:
          task-definition: ${{ steps.task-def.outputs.task-definition }}
          service: ${{ secrets.ECS_SERVICE_NAME }}
          cluster: ${{ secrets.ECS_CLUSTER_NAME }}
          wait-for-service-stability: true
```

- [ ] **Step 2: Add GitHub secrets** (manual step — after `make dev-up`)

After running `make dev-up`, run `terraform -chdir=environments/dev output` and populate these GitHub repository secrets:

| Secret name | Where to get the value |
|---|---|
| `AWS_DEPLOY_ROLE_ARN` | `github_actions_role_arn` output |
| `ECR_REPOSITORY` | `ecr_repository_url` output (repo name only, not full URL) |
| `ECS_CLUSTER_NAME` | `ecs_cluster_name` output |
| `ECS_SERVICE_NAME` | `ecs_service_name` output |
| `ECS_TASK_FAMILY` | `dev-go-crud` (matches the task definition family in the compute module) |

- [ ] **Step 3: Commit**

```bash
git add .github/
git commit -m "feat: GitHub Actions CI/CD — build, push ECR, deploy ECS on merge to main"
```

---

## First Deploy Sequence

After all tasks are complete, this is the order to bring everything up:

```bash
# 1. Create remote state backend (once)
make bootstrap

# 2. Copy and fill dev vars
cp environments/dev/terraform.tfvars.example environments/dev/terraform.tfvars
# edit environments/dev/terraform.tfvars with real values

# 3. Initialize and apply dev
make dev-init
make dev-plan   # review the plan
make dev-up

# 4. Get outputs and populate GitHub secrets
terraform -chdir=environments/dev output

# 5. Push to main — GitHub Actions builds and deploys the Go image to ECS
git push origin main

# 6. Shut down dev when done studying
make dev-down
```
