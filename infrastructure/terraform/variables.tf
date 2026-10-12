variable "aws_region" {
  description = "AWS region where the infrastructure will be deployed."
  type        = string
  default     = "eu-north-1"
}

variable "project_name" {
  description = "Name used for project resources."
  type        = string
  default     = "full-cicd-deployment-platform"
}

variable "environment" {
  description = "Deployment environment."
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
}

variable "availability_zones" {
  description = "Availability Zones used by the network."
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) == 2
    error_message = "Exactly two Availability Zones must be provided."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the public subnets."
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_cidrs) == 2
    error_message = "Exactly two public subnet CIDRs must be provided."
  }
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for the private subnets."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_cidrs) == 2
    error_message = "Exactly two private subnet CIDRs must be provided."
  }
}

variable "db_name" {
  description = "Initial PostgreSQL database name."
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "RDS master username."
  type        = string
  default     = "appadmin"
}

variable "db_password" {
  description = "RDS master password. Supply via TF_VAR_db_password environment variable or a secrets-backed tfvars file. Never commit the value."
  type        = string
  sensitive   = true
}

variable "db_port" {
  description = "PostgreSQL port."
  type        = number
  default     = 5432
}

variable "rds_engine_version" {
  description = "PostgreSQL engine version."
  type        = string
  default     = "16.15"
}

variable "rds_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t3.micro"
}

variable "rds_allocated_storage" {
  description = "Initial RDS storage in GB."
  type        = number
  default     = 20
}

variable "rds_max_allocated_storage" {
  description = "Maximum RDS storage in GB."
  type        = number
  default     = 50
}

variable "rds_backup_retention_period" {
  description = "RDS automated backup retention in days."
  type        = number
  default     = 7
}

variable "ecr_repository_url_override" {
  description = "Override the ECR repository URL. Used by PROD to reuse the DEV ECR repo instead of creating a separate one. Leave empty for dev."
  type        = string
  default     = ""
}

variable "health_check_path" {
  description = "ALB health check path for the ECS target group."
  type        = string
  default     = "/health"
}

variable "deregistration_delay" {
  description = "Seconds ALB waits before deregistering a draining target. Reduced from the AWS default of 300 to shorten rolling deployment time."
  type        = number
  default     = 60
}

variable "ecs_cpu" {
  description = "CPU units for the ECS Fargate task."
  type        = number
  default     = 256
}

variable "ecs_memory" {
  description = "Memory in MiB for the ECS Fargate task."
  type        = number
  default     = 512
}

variable "ecs_desired_count" {
  description = "Desired number of ECS Fargate tasks."
  type        = number
  default     = 2
}

variable "container_image_tag" {
  description = "Docker image tag to deploy from ECR. Updated by the pipeline on each deploy."
  type        = string
  default     = "latest"
}

variable "db_secret_arn" {
  description = "ARN of the Secrets Manager secret containing DB credentials (username, password, dbname). Must be created manually in the target AWS account before running Terraform. Supply via TF_VAR_db_secret_arn or environment-specific tfvars."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:secretsmanager:", var.db_secret_arn))
    error_message = "db_secret_arn must be a valid Secrets Manager ARN starting with arn:aws:secretsmanager:"
  }
}
