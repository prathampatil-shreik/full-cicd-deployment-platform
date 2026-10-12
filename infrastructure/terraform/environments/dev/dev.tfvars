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
ecs_cpu             = 256
ecs_memory          = 512
ecs_desired_count   = 2
health_check_path   = "/health"
container_image_tag = "latest"

# ARN of the Secrets Manager secret holding DB credentials for dev.
# Create this secret manually in the new AWS account before running Terraform.
# Format: {"username":"appadmin","password":"<value>","dbname":"appdb"}
# Then set this ARN as the GitHub Actions secret DB_SECRET_ARN.
# The value below is a placeholder — replace with the real ARN after creation.
db_secret_arn = "REPLACE_WITH_NEW_ACCOUNT_SECRET_ARN"
