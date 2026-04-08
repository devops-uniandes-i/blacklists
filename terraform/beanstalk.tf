# ── Docker Platform (latest AL2023) ──────────────────────────────────────────

data "aws_elastic_beanstalk_solution_stack" "docker" {
  most_recent = true
  name_regex  = "^64bit Amazon Linux 2023 .* running Docker$"
}

# ── Elastic Beanstalk Application ─────────────────────────────────────────────

resource "aws_elastic_beanstalk_application" "blacklist" {
  name        = "${local.name_prefix}-app"
  description = "Blacklist email management service"

  tags = local.tags
}

# ── Application Version ───────────────────────────────────────────────────────

resource "aws_elastic_beanstalk_application_version" "app" {
  name        = "${local.name_prefix}-${var.app_version}"
  application = aws_elastic_beanstalk_application.blacklist.name
  bucket      = aws_s3_bucket.app_bundle.id
  key         = aws_s3_object.app_bundle.key

  tags = merge(local.tags, { Version = var.app_version })
}

# ── Elastic Beanstalk Environment ─────────────────────────────────────────────

resource "aws_elastic_beanstalk_environment" "blacklist" {
  name                = "${local.name_prefix}-env"
  application         = aws_elastic_beanstalk_application.blacklist.name
  solution_stack_name = data.aws_elastic_beanstalk_solution_stack.docker.name
  version_label       = aws_elastic_beanstalk_application_version.app.name

  # ── VPC & Networking ──────────────────────────────────────────────────────

  setting {
    namespace = "aws:ec2:vpc"
    name      = "VPCId"
    value     = aws_vpc.main.id
  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "Subnets"
    value     = join(",", aws_subnet.public[*].id)
  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "ELBSubnets"
    value     = join(",", aws_subnet.public[*].id)
  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "AssociatePublicIpAddress"
    value     = "true"
  }

  # ── Environment Type ──────────────────────────────────────────────────────

  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "EnvironmentType"
    value     = "LoadBalanced"
  }

  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "LoadBalancerType"
    value     = "application"
  }

  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "ServiceRole"
    value     = aws_iam_role.beanstalk_service.arn
  }

  # ── Auto Scaling ──────────────────────────────────────────────────────────

  setting {
    namespace = "aws:autoscaling:asg"
    name      = "MinSize"
    value     = tostring(var.eb_min_instances)
  }

  setting {
    namespace = "aws:autoscaling:asg"
    name      = "MaxSize"
    value     = tostring(var.eb_max_instances)
  }

  # ── Launch Configuration ──────────────────────────────────────────────────

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "InstanceType"
    value     = var.eb_instance_type
  }

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "IamInstanceProfile"
    value     = aws_iam_instance_profile.beanstalk_ec2.name
  }

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "SecurityGroups"
    value     = aws_security_group.app.id
  }

  # ── Deployment Policy ─────────────────────────────────────────────────────

  setting {
    namespace = "aws:elasticbeanstalk:command"
    name      = "DeploymentPolicy"
    value     = var.deployment_policy
  }

  setting {
    namespace = "aws:elasticbeanstalk:command"
    name      = "BatchSizeType"
    value     = var.batch_size_type
  }

  setting {
    namespace = "aws:elasticbeanstalk:command"
    name      = "BatchSize"
    value     = tostring(var.batch_size)
  }

  setting {
    namespace = "aws:elasticbeanstalk:command"
    name      = "Timeout"
    value     = "600"
  }

  # ── Health Reporting ──────────────────────────────────────────────────────

  setting {
    namespace = "aws:elasticbeanstalk:healthreporting:system"
    name      = "SystemType"
    value     = "enhanced"
  }

  setting {
    namespace = "aws:elasticbeanstalk:application"
    name      = "Application Healthcheck URL"
    value     = "/health"
  }

  # ── Default Process (port mapping para Docker) ────────────────────────────

  setting {
    namespace = "aws:elasticbeanstalk:environment:process:default"
    name      = "Port"
    value     = "80"
  }

  setting {
    namespace = "aws:elasticbeanstalk:environment:process:default"
    name      = "Protocol"
    value     = "HTTP"
  }

  setting {
    namespace = "aws:elasticbeanstalk:environment:process:default"
    name      = "HealthCheckPath"
    value     = "/health"
  }

  # ── Environment Variables ─────────────────────────────────────────────────

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "DATABASE_URL"
    value     = "postgresql://${var.db_username}:${var.db_password}@${aws_db_instance.main.address}:5432/${var.db_name}"
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "JWT_SECRET_KEY"
    value     = var.jwt_secret_key
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "AUTH_USERNAME"
    value     = var.auth_username
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "AUTH_PASSWORD"
    value     = var.auth_password
  }

  tags = merge(local.tags, { DeploymentPolicy = var.deployment_policy })
}
