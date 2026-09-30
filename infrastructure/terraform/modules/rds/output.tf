output "db_instance_id" {
  description = "RDS database instance identifier."
  value       = aws_db_instance.this.id
}

output "db_instance_arn" {
  description = "RDS database instance ARN."
  value       = aws_db_instance.this.arn
}

output "db_endpoint" {
  description = "RDS database endpoint."
  value       = aws_db_instance.this.address
}

output "db_port" {
  description = "RDS database port."
  value       = aws_db_instance.this.port
}

output "db_name" {
  description = "Initial database name."
  value       = aws_db_instance.this.db_name
}

output "db_subnet_group_name" {
  description = "RDS subnet group name."
  value       = aws_db_subnet_group.this.name
}
