aws_region   = "eu-north-1"
project_name = "full-cicd-deployment-platform"
environment  = "prod"

vpc_cidr = "10.1.0.0/16"

availability_zones = [
  "eu-north-1a",
  "eu-north-1b",
]

public_subnet_cidrs = [
  "10.1.1.0/24",
  "10.1.2.0/24",
]

private_subnet_cidrs = [
  "10.1.11.0/24",
  "10.1.12.0/24",
]

db_name     = "appdb"
db_username = "appadmin"
# db_password is NOT stored here. Supply via TF_VAR_db_password (GitHub secret).
db_port = 5432

rds_engine_version          = "16.15"
rds_instance_class          = "db.t3.micro"
rds_allocated_storage       = 20
rds_max_allocated_storage   = 50
rds_backup_retention_period = 7

# ── ECS ───────────────────────────────────────────────────────────────────────
ecs_cpu             = 256
ecs_memory          = 512
ecs_desired_count   = 2
health_check_path   = "/health"
container_image_tag = "latest"

# PROD reuses the DEV ECR repository so the same immutable image digest is
# promoted without rebuilding. The pipeline sets this at apply time via:
#   TF_VAR_ecr_repository_url_override = <dev ECR URL from Terraform output>
# Leave empty here; the pipeline injects the correct value.
ecr_repository_url_override = ""

# ARN of the Secrets Manager secret holding DB credentials for prod.
# Create this secret manually in the new AWS account before running prod Terraform.
# Then set PROD_DB_SECRET_ARN as a GitHub Actions secret.
db_secret_arn = "REPLACE_WITH_PROD_SECRET_ARN"
