output "cluster_id" {
  description = "ID of the ECS cluster."
  value       = aws_ecs_cluster.this.id
}

output "cluster_name" {
  description = "Name of the ECS cluster."
  value       = aws_ecs_cluster.this.name
}

output "cluster_arn" {
  description = "ARN of the ECS cluster."
  value       = aws_ecs_cluster.this.arn
}

output "service_name" {
  description = "Name of the ECS service."
  value       = aws_ecs_service.app.name
}

output "service_id" {
  description = "ID of the ECS service."
  value       = aws_ecs_service.app.id
}

output "task_definition_arn" {
  description = "ARN of the latest ECS task definition revision."
  value       = aws_ecs_task_definition.app.arn
}

output "log_group_name" {
  description = "Name of the CloudWatch log group for ECS container logs."
  value       = aws_cloudwatch_log_group.ecs.name
}

output "log_group_arn" {
  description = "ARN of the CloudWatch log group."
  value       = aws_cloudwatch_log_group.ecs.arn
}
