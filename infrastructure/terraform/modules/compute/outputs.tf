output "launch_template_id" {
  description = "ID of the application launch template."
  value       = aws_launch_template.app.id
}

output "launch_template_name" {
  description = "Name of the application launch template."
  value       = aws_launch_template.app.name
}

output "autoscaling_group_name" {
  description = "Name of the application Auto Scaling Group."
  value       = aws_autoscaling_group.app.name
}

output "autoscaling_group_arn" {
  description = "ARN of the application Auto Scaling Group."
  value       = aws_autoscaling_group.app.arn
}

output "iam_role_name" {
  description = "IAM role name attached to application EC2 instances."
  value       = aws_iam_role.ec2.name
}

output "instance_profile_name" {
  description = "IAM instance profile attached to application EC2 instances."
  value       = aws_iam_instance_profile.ec2.name
}
