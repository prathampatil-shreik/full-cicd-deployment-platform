data "aws_caller_identity" "current" {}


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

  ecs_execution_role_arn  = var.ecs_execution_role_arn
  ecs_execution_role_name = var.ecs_execution_role_name

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

module "compute" {
  source = "./modules/compute"

  project_name = var.project_name
  environment  = var.environment

  vpc_id = module.network.vpc_id

  private_subnet_ids = module.network.private_subnet_ids

  app_security_group_id = module.security.app_security_group_id

  ecr_repository_url = local.ecr_repository_url

  nat_gateway_id = module.network.nat_gateway_id

  app_port = 8080

  instance_type = "t3.micro"

  container_image_tag = "latest"

  aws_region = var.aws_region

  target_group_arn = module.alb.target_group_arn

  db_host     = module.rds.db_endpoint
  db_port     = module.rds.db_port
  db_name     = module.rds.db_name
  db_username = var.db_username
  db_password = var.db_password

  asg_min_size         = var.asg_min_size
  asg_desired_capacity = var.asg_desired_capacity
  asg_max_size         = var.asg_max_size

  depends_on = [
    module.network,
    module.security,
    module.ecr,
    module.alb,
  ]
}

resource "aws_autoscaling_policy" "cpu_target_tracking" {
  name                   = "${var.project_name}-${var.environment}-cpu-target"
  autoscaling_group_name = module.compute.autoscaling_group_name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = var.cpu_scale_target
  }
}
