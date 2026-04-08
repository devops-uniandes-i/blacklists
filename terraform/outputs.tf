# ── VPC ───────────────────────────────────────────────────────────────────────

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets (where RDS lives)"
  value       = aws_subnet.private[*].id
}

# ── Security Groups ───────────────────────────────────────────────────────────

output "app_security_group_id" {
  description = "ID of the application security group"
  value       = aws_security_group.app.id
}

output "rds_security_group_id" {
  description = "ID of the RDS security group"
  value       = aws_security_group.rds.id
}

# ── RDS ───────────────────────────────────────────────────────────────────────

output "rds_endpoint" {
  description = "Connection endpoint for the RDS instance (host:port)"
  value       = aws_db_instance.main.endpoint
}

output "rds_host" {
  description = "Hostname of the RDS instance"
  value       = aws_db_instance.main.address
}

output "rds_port" {
  description = "Port of the RDS instance"
  value       = aws_db_instance.main.port
}

output "rds_db_name" {
  description = "Name of the PostgreSQL database"
  value       = aws_db_instance.main.db_name
}

output "rds_instance_id" {
  description = "Identifier of the RDS instance"
  value       = aws_db_instance.main.id
}

output "database_url" {
  description = "Full DATABASE_URL connection string for the application (password hidden)"
  value       = "postgresql://${var.db_username}:****@${aws_db_instance.main.endpoint}/${var.db_name}"
  sensitive   = true
}

# ── Elastic Beanstalk ─────────────────────────────────────────────────────────

output "beanstalk_url" {
  description = "URL of the Elastic Beanstalk environment (access your API here)"
  value       = "http://${aws_elastic_beanstalk_environment.blacklist.cname}"
}

output "beanstalk_env_name" {
  description = "Name of the Elastic Beanstalk environment"
  value       = aws_elastic_beanstalk_environment.blacklist.name
}

output "beanstalk_deployment_policy" {
  description = "Active deployment policy for the current apply"
  value       = var.deployment_policy
}

output "beanstalk_app_version" {
  description = "Active application version label"
  value       = var.app_version
}

output "alb_security_group_id" {
  description = "ID of the ALB security group"
  value       = aws_security_group.alb.id
}
