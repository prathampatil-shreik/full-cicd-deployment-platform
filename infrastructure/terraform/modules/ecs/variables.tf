variable "project_name" {
  description = "Name used for project resources."
  type        = string
}

variable "environment" {
  description = "Deployment environment."
  type        = string
}

variable "aws_region" {
  description = "AWS region for CloudWatch log configuration."
  type        = string
  default     = "us-east-1"
}

variable "ecs_cpu" {
  description = "CPU units for the ECS Fargate task (256 = 0.25 vCPU)."
  type        = number
  default     = 256
}

variable "ecs_memory" {
  description = "Memory in MiB for the ECS Fargate task."
  type        = number
  default     = 512
}

variable "ecs_desired_count" {
  description = "Desired number of ECS tasks."
  type        = number
  default     = 2
}

variable "container_image" {
  description = "Full ECR image URI including tag."
  type        = string
}

variable "container_port" {
  description = "Port the application container listens on."
  type        = number
  default     = 8080
}

variable "private_subnet_ids" {
  description = "Private subnet IDs where ECS tasks will run."
  type        = list(string)
}

variable "ecs_task_security_group_id" {
  description = "Security group ID for ECS Fargate tasks."
  type        = string
}

variable "ecs_target_group_arn" {
  description = "ARN of the ALB target group for ECS tasks."
  type        = string
}

variable "ecs_execution_role_arn" {
  description = "ARN of the ECS task execution IAM role."
  type        = string
}

variable "ecs_execution_role_name" {
  description = "Name of the ECS task execution IAM role (for policy attachment)."
  type        = string
}

variable "db_host" {
  description = "RDS database hostname."
  type        = string
}

variable "db_port" {
  description = "RDS database port."
  type        = number
  default     = 5432
}

variable "db_secret_arn" {
  description = "ARN of the Secrets Manager secret containing DB credentials."
  type        = string
}
