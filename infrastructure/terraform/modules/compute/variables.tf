variable "project_name" {
  description = "Name used for project resources."
  type        = string
}

variable "environment" {
  description = "Deployment environment."
  type        = string
}

variable "aws_region" {
  description = "AWS region used by the EC2 instance for ECR authentication."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where compute resources are deployed."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for EC2 instances."
  type        = list(string)
}

variable "app_security_group_id" {
  description = "Security group ID attached to EC2 instances."
  type        = string
}

variable "ecr_repository_url" {
  description = "ECR repository URL for the application image."
  type        = string
}

variable "nat_gateway_id" {
  description = "NAT gateway ID — passed to establish implicit dependency on NAT before EC2 bootstrap."
  type        = string
}

variable "app_port" {
  description = "Port the application container listens on."
  type        = number
  default     = 8080
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
  default     = "t3.micro"
}

variable "container_image_tag" {
  description = "Docker image tag to deploy from ECR."
  type        = string
  default     = "latest"
}

variable "target_group_arn" {
  description = "ARN of the ALB target group. The ASG registers its instances with this target group."
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

variable "db_name" {
  description = "RDS database name."
  type        = string
}

variable "db_username" {
  description = "RDS database username."
  type        = string
}

variable "db_password" {
  description = "RDS database password."
  type        = string
  sensitive   = true
}

variable "asg_min_size" {
  description = "Minimum number of application instances."
  type        = number
  default     = 2
}

variable "asg_desired_capacity" {
  description = "Desired number of application instances."
  type        = number
  default     = 2
}

variable "asg_max_size" {
  description = "Maximum number of application instances."
  type        = number
  default     = 4
}