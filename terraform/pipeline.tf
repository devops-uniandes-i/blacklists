variable "enable_ci_pipeline" {
  description = "Set to true to create the CodePipeline resources"
  type        = bool
  default     = false
}

variable "repository_branch" {
  description = "Branch that triggers the pipeline automatically"
  type        = string
  default     = "master"
}

variable "codestar_connection_arn" {
  description = "ARN of an existing AWS CodeStar connection to GitHub"
  type        = string
  default     = ""
}

locals {
  pipeline_enabled     = var.enable_ci_pipeline ? 1 : 0
  repository_full_name = trimsuffix(trimprefix(var.github_repo_url, "https://github.com/"), ".git")
}

resource "aws_s3_bucket" "pipeline_artifacts" {
  count         = local.pipeline_enabled
  bucket        = "${local.name_prefix}-pipeline-artifacts-${random_id.bucket_suffix.hex}"
  force_destroy = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-pipeline-artifacts" })
}

resource "aws_s3_bucket_versioning" "pipeline_artifacts" {
  count  = local.pipeline_enabled
  bucket = aws_s3_bucket.pipeline_artifacts[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_iam_role" "codepipeline" {
  count = local.pipeline_enabled
  name  = "${local.name_prefix}-codepipeline-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "codepipeline.amazonaws.com" }
    }]
  })

  tags = merge(local.tags, { Name = "${local.name_prefix}-codepipeline-role" })
}

resource "aws_iam_role_policy" "codepipeline" {
  count = local.pipeline_enabled
  name  = "${local.name_prefix}-codepipeline-policy"
  role  = aws_iam_role.codepipeline[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "PipelineArtifacts"
        Effect = "Allow"
        Action = [
          "s3:GetBucketVersioning",
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject"
        ]
        Resource = [
          aws_s3_bucket.pipeline_artifacts[0].arn,
          "${aws_s3_bucket.pipeline_artifacts[0].arn}/*"
        ]
      },
      {
        Sid    = "StartCodeBuild"
        Effect = "Allow"
        Action = [
          "codebuild:BatchGetBuilds",
          "codebuild:StartBuild"
        ]
        Resource = aws_codebuild_project.blacklist.arn
      },
      {
        Sid    = "UseGitHubConnection"
        Effect = "Allow"
        Action = [
          "codestar-connections:UseConnection"
        ]
        Resource = var.codestar_connection_arn
      },
      {
        Sid    = "DeployToElasticBeanstalk"
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeScalingActivities",
          "autoscaling:ResumeProcesses",
          "autoscaling:SuspendProcesses",
          "cloudformation:GetTemplate",
          "cloudformation:DescribeStackResource",
          "cloudformation:DescribeStackResources",
          "cloudformation:DescribeStacks",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeLaunchTemplateVersions",
          "ec2:DescribeSubnets",
          "elasticbeanstalk:CreateApplicationVersion",
          "elasticbeanstalk:DescribeApplicationVersions",
          "elasticbeanstalk:DescribeEnvironments",
          "elasticbeanstalk:DescribeEvents",
          "elasticbeanstalk:UpdateEnvironment"
        ]
        Resource = "*"
      },
      {
        Sid    = "ElasticBeanstalkServiceBucket"
        Effect = "Allow"
        Action = [
          "s3:CreateBucket",
          "s3:GetBucketAcl",
          "s3:GetBucketPolicy",
          "s3:GetBucketLocation",
          "s3:GetObjectAcl",
          "s3:ListBucket",
          "s3:DeleteObject",
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:PutObjectAcl"
        ]
        Resource = [
          "arn:aws:s3:::elasticbeanstalk-${var.aws_region}-${data.aws_caller_identity.current.account_id}",
          "arn:aws:s3:::elasticbeanstalk-${var.aws_region}-${data.aws_caller_identity.current.account_id}/*"
        ]
      },
      {
        Sid    = "ElasticBeanstalkManagedEnvResources"
        Effect = "Allow"
        Action = [
          "s3:GetBucketLocation",
          "s3:ListBucket",
          "s3:GetObject",
          "s3:GetObjectVersion"
        ]
        Resource = [
          "arn:aws:s3:::elasticbeanstalk-env-resources-${var.aws_region}",
          "arn:aws:s3:::elasticbeanstalk-env-resources-${var.aws_region}/*"
        ]
      }
    ]
  })
}

resource "aws_codepipeline" "app_pipeline" {
  count          = local.pipeline_enabled
  name           = "${local.name_prefix}-pipeline"
  role_arn       = aws_iam_role.codepipeline[0].arn
  pipeline_type  = "V2"
  execution_mode = "QUEUED"

  trigger {
    provider_type = "CodeStarSourceConnection"

    git_configuration {
      source_action_name = "Source"

      push {
        branches {
          includes = [var.repository_branch]
        }
      }

      pull_request {
        events = ["OPEN", "UPDATED", "CLOSED"]

        branches {
          includes = [var.repository_branch]
        }
      }
    }
  }

  artifact_store {
    location = aws_s3_bucket.pipeline_artifacts[0].bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        ConnectionArn    = var.codestar_connection_arn
        FullRepositoryId = local.repository_full_name
        BranchName       = var.repository_branch
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]

      configuration = {
        ProjectName = aws_codebuild_project.blacklist.name
      }
    }
  }

  stage {
    name = "Deploy"

    on_failure {
      result = "ROLLBACK"
    }

    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "ElasticBeanstalk"
      version         = "1"
      region          = "us-east-1"
      input_artifacts = ["build_output"]

      configuration = {
        ApplicationName = "blacklist-dev-app"
        EnvironmentName = "blacklist-dev-env"
      }
    }
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-pipeline" })
}
