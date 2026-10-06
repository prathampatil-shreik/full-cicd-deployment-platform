variable "aws_region" {
  description = "AWS region where the infrastructure will be deployed."
  type        = string
  default     = "us-east-1"
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
  description = "RDS master password."
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
  default     = "16.4"
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

variable "asg_min_size" {
  description = "Minimum application instances."
  type        = number
  default     = 2
}

variable "asg_desired_capacity" {
  description = "Desired application instances."
  type        = number
  default     = 2
}

variable "asg_max_size" {
  description = "Maximum application instances."
  type        = number
  default     = 4
}

variable "cpu_scale_target" {
  description = "CPU utilisation percentage target for ASG target-tracking scaling policy."
  type        = number
  default     = 60
}

variable "instance_type" {
  description = "EC2 instance type for application servers."
  type        = string
  default     = "t3.micro"
}

variable "ecr_repository_url_override" {
  description = "Override the ECR repository URL. Used by PROD to reuse the DEV ECR repo instead of creating a separate one."
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
  description = "Docker image tag to deploy from ECR."
  type        = string
  default     = "latest"
}

variable "db_secret_arn" {
  description = "ARN of the Secrets Manager secret containing DB credentials (username, password, dbname)."
  type        = string
}
