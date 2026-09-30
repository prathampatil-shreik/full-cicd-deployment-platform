variable "project_name" {
  description = "Name used for project resources."
  type        = string
}

variable "environment" {
  description = "Deployment environment."
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC where security groups will be created."
  type        = string
}

variable "app_port" {
  description = "Port exposed by the application."
  type        = number
  default     = 8080
}

variable "db_port" {
  description = "Port used by the database."
  type        = number
  default     = 5432
}