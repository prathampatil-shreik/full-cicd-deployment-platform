data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

module "network" {
  source = "./modules/network"

  project_name = var.project_name
  environment  = var.environment

  vpc_cidr = var.vpc_cidr

  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
}

module "security" {
  source = "./modules/security"

  project_name = var.project_name
  environment  = var.environment

  vpc_id = module.network.vpc_id

  app_port = 8080
  db_port  = 5432
}

module "ecr" {
  source = "./modules/ecr"

  project_name = var.project_name
  environment  = var.environment
}

locals {
  # PROD reuses the DEV ECR repository URL so the same immutable image digest
  # is promoted without rebuilding. Supply ecr_repository_url_override only in
  # prod.tfvars — leave it empty ("") for dev so the ECR module URL is used.
  ecr_repository_url = var.ecr_repository_url_override != "" ? var.ecr_repository_url_override : module.ecr.repository_url
  container_image    = "${local.ecr_repository_url}:${var.container_image_tag}"
}

module "rds" {
  source = "./modules/rds"

  project_name = var.project_name
  environment  = var.environment

  private_subnet_ids    = module.network.private_subnet_ids
  rds_security_group_id = module.security.rds_security_group_id

  db_name     = var.db_name
  db_username = var.db_username
  db_password = var.db_password
  db_port     = var.db_port

  engine_version          = var.rds_engine_version
  instance_class          = var.rds_instance_class
  allocated_storage       = var.rds_allocated_storage
  max_allocated_storage   = var.rds_max_allocated_storage
  backup_retention_period = var.rds_backup_retention_period
}

module "alb" {
  source = "./modules/alb"

  project_name = var.project_name
  environment  = var.environment

  vpc_id            = module.network.vpc_id
  public_subnet_ids = module.network.public_subnet_ids

  alb_security_group_id = module.security.alb_security_group_id

  target_port          = 8080
  health_check_path    = var.health_check_path
  deregistration_delay = var.deregistration_delay

  depends_on = [
    module.network,
    module.security,
  ]
}

module "ecs" {
  source = "./modules/ecs"

  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.aws_region

  ecs_cpu           = var.ecs_cpu
  ecs_memory        = var.ecs_memory
  ecs_desired_count = var.ecs_desired_count

  container_image = local.container_image
  container_port  = 8080

  private_subnet_ids         = module.network.private_subnet_ids
  ecs_task_security_group_id = module.security.ecs_task_security_group_id
  ecs_target_group_arn       = module.alb.ecs_target_group_arn

  db_host       = module.rds.db_endpoint
  db_port       = var.db_port
  db_secret_arn = var.db_secret_arn

  depends_on = [
    module.network,
    module.security,
    module.alb,
    module.rds,
  ]
}

