aws_region   = "us-east-1"
project_name = "full-cicd-deployment-platform"
environment  = "prod"

vpc_cidr = "10.1.0.0/16"

availability_zones = [
  "us-east-1a",
  "us-east-1b",
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
db_port     = 5432

rds_engine_version          = "16.4"
rds_instance_class          = "db.t3.micro"
rds_allocated_storage       = 20
rds_max_allocated_storage   = 50
rds_backup_retention_period = 7

asg_min_size         = 2
asg_desired_capacity = 2
asg_max_size         = 4

cpu_scale_target = 60

# Reuse the DEV ECR repository — PROD pulls the same image that was built and
# verified in DEV. No separate ECR repo is created for PROD.
ecr_repository_url_override = "925213028316.dkr.ecr.us-east-1.amazonaws.com/full-cicd-deployment-platform-dev-app"
