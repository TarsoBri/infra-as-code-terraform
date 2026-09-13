# infra-as-code-terraform

AWS infrastructure for a Go CRUD API. Terraform modules organized by layer.

## Architecture

```
Internet → ALB (public subnets) → ECS Fargate tasks (private subnets)
                                       ↓              ↓
                                     RDS          ElastiCache
                                  PostgreSQL         Redis

CloudFront → S3 (static assets)
```

## Module dependency order

```
networking → (security + data) → compute → delivery
```

## First-time setup

1. `make bootstrap` — creates S3 bucket + DynamoDB table for remote state (run once)
2. Copy `environments/dev/terraform.tfvars.example` to `environments/dev/terraform.tfvars` and fill in values
3. `make dev-init` — initializes Terraform with the remote backend
4. `make dev-up` — provisions all dev infrastructure
5. After `make dev-up`, run `terraform -chdir=environments/dev output` and populate GitHub repository secrets

## Daily workflow

| Command           | Effect                                     |
| ----------------- | ------------------------------------------ |
| `make dev-up`     | Spin up dev infrastructure                 |
| `make dev-down`   | Tear down dev infrastructure (zero cost)   |
| `make dev-plan`   | Preview changes before applying            |
| `make prod-plan`  | Preview prod changes (never auto-approved) |
| `make prod-apply` | Apply prod changes (requires confirmation) |

## GitHub repository secrets required for CI/CD

After `make dev-up`, populate these in GitHub → Settings → Secrets:

| Secret                | Source                           |
| --------------------- | -------------------------------- |
| `AWS_DEPLOY_ROLE_ARN` | `github_actions_role_arn` output |
| `ECR_REPOSITORY`      | `ecr_repository_url` output      |
| `ECS_CLUSTER_NAME`    | `ecs_cluster_name` output        |
| `ECS_SERVICE_NAME`    | `ecs_service_name` output        |
| `ECS_TASK_FAMILY`     | `dev-go-crud`                    |

## Security invariants

- No credentials in any `.tf` file
- RDS and ElastiCache are private-subnet-only
- ECS tasks run in private subnets; only ALB is public
- All secrets fetched at runtime via IAM
- `*.tfvars` with real values are gitignored

## Out of scope (apply later)

- HTTPS / ACM certificate — add after pointing a domain to the ALB
- WAF rules on CloudFront — add after traffic patterns are known
- VPC Flow Logs / CloudTrail — add for compliance requirements
