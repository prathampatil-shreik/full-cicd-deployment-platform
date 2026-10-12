aws_region   = "eu-north-1"
project_name = "full-cicd-deployment-platform"
environment  = "dev"

vpc_cidr = "10.0.0.0/16"

availability_zones = [
  "eu-north-1a",
  "eu-north-1b"
]

public_subnet_cidrs = [
  "10.0.1.0/24",
  "10.0.2.0/24"
]

private_subnet_cidrs = [
  "10.0.11.0/24",
  "10.0.12.0/24"
]

db_name     = "appdb"
db_username = "appadmin"
# db_password is NOT stored here. Supply it via:
#   - GitHub Actions secret DB_PASSWORD (set as TF_VAR_db_password)
#   - Locally: export TF_VAR_db_password="<your-password>"
db_port = 5432

ecr_repository_url_override = ""

# ── ECS ───────────────────────────────────────────────────────────────────────
ecs_cpu             = 512
ecs_memory          = 1024
ecs_desired_count   = 2
health_check_path   = "/health"
container_image_tag = "latest"

# db_secret_arn is NOT stored here. Supply it via:
#   - GitHub Actions secret DB_SECRET_ARN (set as TF_VAR_db_secret_arn)
#   - Locally: export TF_VAR_db_secret_arn="arn:aws:secretsmanager:..."
