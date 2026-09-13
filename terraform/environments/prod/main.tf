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
