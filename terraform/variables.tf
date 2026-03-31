variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used as prefix for all resources"
  type        = string
  default     = "blacklist"
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  default     = "dev"
}

# ── Networking ────────────────────────────────────────────────────────────────

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for the two private subnets (RDS requires at least two AZs)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the public subnets (application layer)"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

# ── RDS ───────────────────────────────────────────────────────────────────────

variable "db_name" {
  description = "Name of the PostgreSQL database"
  type        = string
  default     = "blacklistdb"
}

variable "db_username" {
  description = "Master username for the RDS instance"
  type        = string
  default     = "postgres"
  sensitive   = true
}

variable "db_password" {
  description = "Master password for the RDS instance (min 8 chars)"
  type        = string
  sensitive   = true
}

variable "db_instance_class" {
  description = "RDS instance type"
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "Allocated storage for RDS in GB"
  type        = number
  default     = 20
}

variable "db_engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "16.3"
}

variable "db_multi_az" {
  description = "Enable Multi-AZ deployment for high availability"
  type        = bool
  default     = false
}

variable "db_deletion_protection" {
  description = "Prevent accidental deletion of the RDS instance"
  type        = bool
  default     = false
}

variable "db_backup_retention_period" {
  description = "Number of days to retain automated backups (0 disables backups; free tier requires 0)"
  type        = number
  default     = 0
}

variable "db_skip_final_snapshot" {
  description = "Skip final snapshot when destroying the RDS instance"
  type        = bool
  default     = true
}

# ── Application access ────────────────────────────────────────────────────────

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to connect to RDS (e.g. your bastion or CI runner IP)"
  type        = list(string)
  default     = []
}
