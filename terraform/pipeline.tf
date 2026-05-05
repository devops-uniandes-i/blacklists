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

variable "ecs_cluster_name" {
  description = "Name of the manually-created ECS Fargate cluster"
  type        = string
  default     = ""
}

variable "ecs_service_name" {
  description = "Name of the manually-created ECS Fargate service"
  type        = string
  default     = ""
}

variable "ecr_repository_url" {
  description = "URL of the manually-created ECR repository (e.g. 123456789.dkr.ecr.us-east-1.amazonaws.com/my-app)"
  type        = string
  default     = ""
}

variable "codedeploy_app_name" {
  description = "Name of the CodeDeploy application for ECS Blue/Green deployment"
  type        = string
  default     = ""
}

variable "codedeploy_deployment_group" {
  description = "Name of the CodeDeploy deployment group for ECS Blue/Green deployment"
  type        = string
  default     = ""
}

locals {
  pipeline_enabled     = var.enable_ci_pipeline ? 1 : 0
  repository_full_name = trimsuffix(trimprefix(var.github_repo_url, "https://github.com/"), ".git")
  ecr_repo_name        = var.ecr_repository_url != "" ? element(split("/", var.ecr_repository_url), length(split("/", var.ecr_repository_url)) - 1) : ""
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
        Sid    = "DeployToECS"
        Effect = "Allow"
        Action = [
          "ecs:DescribeServices",
          "ecs:DescribeTaskDefinition",
          "ecs:DescribeTasks",
          "ecs:ListTasks",
          "ecs:RegisterTaskDefinition",
          "ecs:UpdateService",
          "ecs:TagResource"
        ]
        Resource = "*"
      },
      {
        Sid    = "CodeDeploy"
        Effect = "Allow"
        Action = [
          "codedeploy:CreateDeployment",
          "codedeploy:GetApplication",
          "codedeploy:GetApplicationRevision",
          "codedeploy:GetDeployment",
          "codedeploy:GetDeploymentConfig",
          "codedeploy:RegisterApplicationRevision"
        ]
        Resource = "*"
      },
      {
        Sid      = "PassRoleForECS"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = "*"
        Condition = {
          StringEqualsIfExists = {
            "iam:PassedToService" = [
              "ecs-tasks.amazonaws.com"
            ]
          }
        }
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

    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "CodeDeployToECS"
      version         = "1"
      input_artifacts = ["build_output"]

      configuration = {
        ApplicationName                = var.codedeploy_app_name
        DeploymentGroupName            = var.codedeploy_deployment_group
        TaskDefinitionTemplateArtifact = "build_output"
        TaskDefinitionTemplatePath     = "taskdef.json"
        AppSpecTemplateArtifact        = "build_output"
        AppSpecTemplatePath            = "appspec.json"
        Image1ArtifactName             = "build_output"
        Image1ContainerName            = "IMAGE1_NAME"
      }
    }
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-pipeline" })
}
