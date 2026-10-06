variable "project_name" {
  description = "Name used for project resources."
  type        = string
}

variable "environment" {
  description = "Deployment environment."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the ALB and target group will be deployed."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for the internet-facing ALB."
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "Security group ID attached to the ALB."
  type        = string
}

variable "target_port" {
  description = "Port the application instances listen on."
  type        = number
  default     = 8080
}

variable "health_check_path" {
  description = "Health check path for the ECS target group."
  type        = string
  default     = "/health"
}

variable "deregistration_delay" {
  description = "Seconds ALB waits before deregistering a draining target. Reduce from the AWS default of 300 to shorten rolling deployment time."
  type        = number
  default     = 60
}
