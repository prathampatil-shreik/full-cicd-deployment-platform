output "alb_security_group_id" {
  description = "Security group ID for the Application Load Balancer."
  value       = aws_security_group.alb.id
}

output "app_security_group_id" {
  description = "Security group ID for application servers."
  value       = aws_security_group.app.id
}

output "rds_security_group_id" {
  description = "Security group ID for RDS."
  value       = aws_security_group.rds.id
}

output "ecs_task_security_group_id" {
  description = "Security group ID for ECS Fargate tasks."
  value       = aws_security_group.ecs_task.id
}