locals {
  name_prefix = "${var.project_name}-${var.environment}"

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# ── Availability Zones ────────────────────────────────────────────────────────

data "aws_availability_zones" "available" {
  state = "available"
}

# ── VPC ───────────────────────────────────────────────────────────────────────

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-vpc" })
}

# ── Internet Gateway ──────────────────────────────────────────────────────────

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.tags, { Name = "${local.name_prefix}-igw" })
}

# ── Public Subnets ────────────────────────────────────────────────────────────

resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-public-${count.index + 1}" })
}

# ── Private Subnets (RDS) ─────────────────────────────────────────────────────

resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = merge(local.tags, { Name = "${local.name_prefix}-private-${count.index + 1}" })
}

# ── Route Tables ──────────────────────────────────────────────────────────────

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-public-rt" })
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ── Security Group: Application ───────────────────────────────────────────────

resource "aws_security_group" "app" {
  name        = "${local.name_prefix}-app-sg"
  description = "Security group for the Blacklist application"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-app-sg" })
}

# ── Security Group: RDS ───────────────────────────────────────────────────────

resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-rds-sg"
  description = "Security group for the RDS PostgreSQL instance"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from application layer"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  dynamic "ingress" {
    for_each = length(var.allowed_cidr_blocks) > 0 ? [1] : []
    content {
      description = "PostgreSQL from allowed CIDRs (e.g. bastion / CI)"
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = var.allowed_cidr_blocks
    }
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-rds-sg" })
}

# ── RDS Subnet Group ──────────────────────────────────────────────────────────

resource "aws_db_subnet_group" "main" {
  name        = "${local.name_prefix}-db-subnet-group"
  description = "Subnet group for ${local.name_prefix} RDS instance"
  subnet_ids  = aws_subnet.private[*].id

  tags = merge(local.tags, { Name = "${local.name_prefix}-db-subnet-group" })
}

# ── RDS Parameter Group ───────────────────────────────────────────────────────

resource "aws_db_parameter_group" "main" {
  name        = "${local.name_prefix}-pg16"
  family      = "postgres16"
  description = "Parameter group for ${local.name_prefix} PostgreSQL 16"

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-pg16" })
}

# ── RDS PostgreSQL Instance ───────────────────────────────────────────────────

resource "aws_db_instance" "main" {
  identifier = "${local.name_prefix}-postgres"

  # Engine
  engine         = "postgres"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  # Storage
  allocated_storage = var.db_allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  # Credentials
  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  # Networking
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  # Configuration
  parameter_group_name = aws_db_parameter_group.main.name
  multi_az             = var.db_multi_az

  # Backup & maintenance
  backup_retention_period = var.db_backup_retention_period
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"

  # Protection
  deletion_protection       = var.db_deletion_protection
  skip_final_snapshot       = var.db_skip_final_snapshot
  final_snapshot_identifier = var.db_skip_final_snapshot ? null : "${local.name_prefix}-final-snapshot"

  # Monitoring
  performance_insights_enabled = false

  tags = merge(local.tags, { Name = "${local.name_prefix}-postgres" })
}
