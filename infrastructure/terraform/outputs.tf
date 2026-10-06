output "aws_account_id" {
  description = "AWS account ID used by Terraform."
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS region used by Terraform."
  value       = var.aws_region
}

output "ecr_repository_name" {
  description = "ECR repository name."
  value       = module.ecr.repository_name
}

output "ecr_repository_url" {
  description = "ECR repository URL."
  value       = local.ecr_repository_url
}

output "ecr_repository_arn" {
  description = "ECR repository ARN."
  value       = module.ecr.repository_arn
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer. Access the app at http://<alb_dns_name>"
  value       = module.alb.alb_dns_name
}

output "alb_arn" {
  description = "ARN of the Application Load Balancer."
  value       = module.alb.alb_arn
}

output "target_group_arn" {
  description = "ARN of the legacy EC2 instance ALB target group."
  value       = module.alb.target_group_arn
}

output "ecs_target_group_arn" {
  description = "ARN of the ECS ip-type ALB target group."
  value       = module.alb.ecs_target_group_arn
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster."
  value       = module.ecs.cluster_name
}

output "ecs_service_name" {
  description = "Name of the ECS service."
  value       = module.ecs.service_name
}

output "ecs_task_definition_arn" {
  description = "ARN of the latest ECS task definition revision."
  value       = module.ecs.task_definition_arn
}

output "ecs_task_security_group_id" {
  description = "Security group ID for ECS Fargate tasks."
  value       = module.security.ecs_task_security_group_id
}

output "ecs_log_group_name" {
  description = "CloudWatch log group name for ECS container logs."
  value       = module.ecs.log_group_name
}
