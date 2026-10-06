output "alb_id" {
  description = "ID of the Application Load Balancer."
  value       = aws_lb.app.id
}

output "alb_arn" {
  description = "ARN of the Application Load Balancer."
  value       = aws_lb.app.arn
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer."
  value       = aws_lb.app.dns_name
}

output "alb_zone_id" {
  description = "Canonical hosted zone ID of the Application Load Balancer (for Route 53 alias records)."
  value       = aws_lb.app.zone_id
}

output "target_group_arn" {
  description = "ARN of the legacy EC2 instance target group."
  value       = aws_lb_target_group.app.arn
}

output "target_group_name" {
  description = "Name of the legacy EC2 instance target group."
  value       = aws_lb_target_group.app.name
}

output "ecs_target_group_arn" {
  description = "ARN of the ECS ip-type target group."
  value       = aws_lb_target_group.ecs.arn
}

output "ecs_target_group_name" {
  description = "Name of the ECS ip-type target group."
  value       = aws_lb_target_group.ecs.name
}

output "listener_arn" {
  description = "ARN of the HTTP listener."
  value       = aws_lb_listener.http.arn
}
