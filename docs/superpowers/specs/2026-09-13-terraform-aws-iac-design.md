# Terraform AWS IaC — Design Spec

**Date:** 2026-09-13  
**Author:** tarsobrietzkeiracet@gmail.com  
**Status:** Approved

---

## Overview

A production-grade Terraform IaC project for AWS, simulating a real-world infrastructure for a Go CRUD API. Organized by layered modules, with separate `dev` and `prod` environments sharing the same module code. No credentials ever appear in code or git history.

---

## Application Context

- **Runtime:** Go (simple CRUD REST API)
- **Container registry:** AWS ECR
- **Database:** PostgreSQL on RDS
- **Cache:** Redis on ElastiCache
- **Delivery:** Static assets / artifacts via S3 + CloudFront

---

## Project Structure

```
infra-as-code-terraform/
│
├── bootstrap/                  # One-time setup: S3 bucket + DynamoDB for remote state
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
│
├── modules/                    # Reusable, environment-agnostic modules
│   ├── networking/             # VPC, subnets, IGW, NAT GW, SGs, route tables
│   ├── compute/                # ECS cluster, Fargate task def, ALB, Auto Scaling, ECR
│   ├── data/                   # RDS PostgreSQL, ElastiCache Redis
│   ├── delivery/               # CloudFront distribution, S3 bucket
│   └── security/               # IAM roles/policies, Secrets Manager, SSM Parameter Store
│
├── environments/
│   ├── dev/
│   │   ├── main.tf             # Calls modules with dev-sized variables
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── terraform.tfvars.example
│   │   └── backend.tf          # S3 remote state (dev key)
│   └── prod/
│       ├── main.tf             # Calls modules with prod-sized variables
│       ├── variables.tf
│       ├── outputs.tf
│       ├── terraform.tfvars.example
│       └── backend.tf          # S3 remote state (prod key)
│
├── app/                        # Go CRUD API (minimal, for infra validation)
│   ├── main.go
│   ├── go.mod
│   └── Dockerfile
├── .github/
│   └── workflows/
│       └── deploy.yml          # CI/CD: build → push ECR → deploy ECS on merge to main
├── Makefile                    # Single entrypoint for all environment operations
├── .gitignore                  # Ignores *.tfvars (secrets), .terraform/, *.tfstate
└── README.md
```

**Rules:**
- Modules contain zero hardcoded environment logic — all sizing and config comes from variables
- `terraform.tfvars` files with real values are gitignored; only `.tfvars.example` is committed
- Code comments appear above every resource block explaining what it does and why

---

## Module: networking

**Purpose:** Foundation layer. Creates the VPC and all network primitives other modules depend on.

**Resources:**
- VPC with DNS hostnames enabled
- Public subnets (ALB-facing)
- Private subnets (ECS tasks, RDS, ElastiCache — no internet access)
- Internet Gateway (public traffic in/out)
- NAT Gateway (private subnets can reach internet for ECR pulls, etc.)
- Route tables for public and private subnets
- Security Groups:
  - `sg_alb` — allows HTTP (80) and HTTPS (443) from `0.0.0.0/0`
  - `sg_ecs` — allows all traffic only from `sg_alb`
  - `sg_rds` — allows PostgreSQL (5432) only from `sg_ecs`
  - `sg_elasticache` — allows Redis (6379) only from `sg_ecs`

**Outputs:** `vpc_id`, `public_subnet_ids`, `private_subnet_ids`, `sg_alb_id`, `sg_ecs_id`, `sg_rds_id`, `sg_elasticache_id`

**Dev vs Prod:**

| Resource | Dev | Prod |
|---|---|---|
| Availability Zones | 1 | 2 |
| Public subnets | 1 | 2 |
| Private subnets | 1 | 2 |
| NAT Gateway | 1 | 1 per AZ |

---

## Module: compute

**Purpose:** Runs the Go API containers. Handles traffic routing, scaling, and container image storage.

**Resources:**
- ECR Repository — stores the Go Docker image (tagged by environment)
- ECS Cluster — logical Fargate cluster
- ECS Task Definition — CPU, memory, container image, env vars and secrets injected at runtime
- ECS Service — maintains desired task count, registers tasks with ALB target group
- Application Load Balancer (ALB) — public-facing, in public subnets
- ALB Listener + Target Group — routes HTTP to healthy ECS tasks
- Auto Scaling Target + Policy — scales on CPU > 60%

**Traffic flow:**
```
Internet → ALB (public subnet, sg_alb) → ECS Tasks (private subnet, sg_ecs)
```

**Dev vs Prod:**

| Config | Dev | Prod |
|---|---|---|
| Task CPU | 256 | 512 |
| Task Memory | 512 MB | 1024 MB |
| Min tasks | 1 | 2 |
| Max tasks | 2 | 6 |

**Outputs:** `alb_dns_name`, `ecs_cluster_name`, `ecs_service_name`, `ecr_repository_url`

---

## Module: data

**Purpose:** Persistent storage layer. RDS and ElastiCache are private-only with no public endpoints.

**RDS PostgreSQL:**
- Deployed in private subnets via a DB subnet group
- `deletion_protection = true` in prod, `false` in dev
- Automated backups: 7-day retention in prod, 1-day in dev
- `skip_final_snapshot = true` in dev, `false` in prod
- Master credentials stored in Secrets Manager — never in Terraform variables or state

**ElastiCache Redis:**
- Deployed in private subnets via a cache subnet group
- Accessible only from `sg_ecs`

**Dev vs Prod:**

| Config | Dev | Prod |
|---|---|---|
| RDS instance | `db.t3.micro` | `db.t3.small` |
| RDS Multi-AZ | No | Yes |
| RDS backup retention | 1 day | 7 days |
| Redis node type | `cache.t3.micro` | `cache.t3.small` |
| Redis nodes | 1 | 2 |

**Outputs:** `db_endpoint`, `db_port`, `redis_endpoint`, `redis_port`

---

## Module: delivery

**Purpose:** Serves static assets or build artifacts securely via CloudFront. S3 bucket is never publicly accessible.

**Resources:**
- S3 Bucket — private, versioning enabled in prod
- CloudFront Distribution — HTTPS termination, global CDN
- Origin Access Control (OAC) — only CloudFront can read from S3
- Bucket Policy — enforces OAC-only access

**Dev vs Prod:**

| Config | Dev | Prod |
|---|---|---|
| S3 versioning | Disabled | Enabled |
| CloudFront price class | `PriceClass_100` | `PriceClass_All` |

**Outputs:** `cloudfront_domain`, `s3_bucket_name`, `s3_bucket_arn`

---

## Module: security

**Purpose:** All IAM, secrets, and configuration management. This is where the "no credentials in code" contract is enforced.

**IAM Roles:**
- **ECS Execution Role** — used by ECS control plane to pull images from ECR and inject secrets from Secrets Manager/SSM at task startup
- **ECS Task Role** — used by the running Go container (e.g., S3 write, SSM read). Least-privilege — only what the app actually needs

**Secrets Manager** (sensitive, rotatable):
```
/go-crud/{env}/db/password
/go-crud/{env}/db/username
```

**SSM Parameter Store — SecureString** (config, not credentials):
```
/go-crud/{env}/app/port
/go-crud/{env}/app/log_level
/go-crud/{env}/redis/endpoint
```

**Secret injection flow:**
```
ECS Task starts
  → ECS Execution Role fetches from Secrets Manager + SSM
    → Injected as environment variables into the container
      → Go app reads via os.Getenv() — no secrets in code or state
```

**What never appears in code or git:**
- DB passwords or usernames
- Any API keys or tokens
- `.tfvars` files with real values

**Outputs:** `ecs_execution_role_arn`, `ecs_task_role_arn`, `db_secret_arn`

---

## Bootstrap

Run **once** before initializing any environment. Uses local state temporarily.

**Resources:**
- S3 bucket with versioning and server-side encryption (AES-256)
- DynamoDB table with `LockID` hash key for state locking

**Remote state layout:**
```
s3://go-crud-terraform-state/
  dev/terraform.tfstate
  prod/terraform.tfstate
```

---

## Environments

Both `dev` and `prod` call the same five modules. Variables alone control sizing, AZ count, backup retention, and protection flags.

**`environments/dev/backend.tf`:**
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

**`environments/prod/backend.tf`:** same, with `key = "prod/terraform.tfstate"`

---

## Makefile

Single entrypoint for all environment operations.

```makefile
# --- Dev ---
dev-init:
    terraform -chdir=environments/dev init

dev-plan:
    terraform -chdir=environments/dev plan

dev-up:
    terraform -chdir=environments/dev apply -auto-approve

dev-down:
    terraform -chdir=environments/dev destroy -auto-approve

# --- Prod (no -auto-approve: always prompts) ---
prod-init:
    terraform -chdir=environments/prod init

prod-plan:
    terraform -chdir=environments/prod plan

prod-apply:
    terraform -chdir=environments/prod apply

# --- Bootstrap (run once) ---
bootstrap:
    terraform -chdir=bootstrap init && terraform -chdir=bootstrap apply -auto-approve
```

Dev can be destroyed and recreated freely. Prod **never** uses `-auto-approve`.

---

## Security Invariants

1. No credentials in any `.tf` file or variable default
2. No S3 bucket with public access
3. RDS and ElastiCache are private-subnet-only
4. ECS tasks run in private subnets; only ALB is public
5. All secrets fetched at runtime via IAM — never baked into images or state
6. `*.tfvars` with real values are gitignored
7. Prod has `deletion_protection = true` and `skip_final_snapshot = false`

---

## Tagging Strategy

All resources share a common tag set applied via `default_tags` on the AWS provider:

```hcl
default_tags {
  tags = {
    Project     = "go-crud"
    Environment = var.env
    ManagedBy   = "terraform"
  }
}
```

---

## CI/CD Pipeline (GitHub Actions)

On every push/merge to `main`, a GitHub Actions workflow will:

1. Build the Go Docker image
2. Authenticate to AWS via OIDC (no long-lived AWS keys in GitHub secrets)
3. Push the image to ECR (tagged with the commit SHA)
4. Update the ECS service to force a new deployment with the new image

**Workflow file:** `.github/workflows/deploy.yml`

**AWS OIDC:** An IAM OIDC provider and a deploy role are created in the `security` module. GitHub Actions assumes this role via `aws-actions/configure-aws-credentials` — no static `AWS_ACCESS_KEY_ID` stored in GitHub.

---

## Go CRUD API (test application)

A minimal Go REST API to validate the infrastructure end-to-end.

**Endpoints:**
```
POST   /items        # Create an item
GET    /items        # List all items
GET    /items/{id}   # Get one item
PUT    /items/{id}   # Update an item
DELETE /items/{id}   # Delete an item
GET    /health       # Health check (used by ALB target group)
```

**Stack:**
- Standard library `net/http` or `chi` router
- `pgx` for PostgreSQL connection
- Reads DB connection string from environment variables (injected by ECS from Secrets Manager)
- Reads Redis endpoint from environment variables (injected from SSM)
- Packaged as a `Dockerfile` at the repo root

**Location:** `app/` directory at the repo root

---

## Out of Scope (apply later)

- **HTTPS / ACM certificate** — requires a real domain. Add after pointing a domain to the ALB.
- **WAF rules on CloudFront** — add after CloudFront is live and traffic patterns are known.
- **VPC Flow Logs / CloudTrail** — add for compliance/audit requirements in a later phase.
