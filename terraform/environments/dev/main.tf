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
  # Placeholder image — replaced by CI/CD after the first push to main
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
