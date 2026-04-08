# ── S3 Bucket for Application Bundles ────────────────────────────────────────

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "app_bundle" {
  bucket        = "${local.name_prefix}-app-bundles-${random_id.bucket_suffix.hex}"
  force_destroy = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-app-bundles" })
}

resource "aws_s3_bucket_versioning" "app_bundle" {
  bucket = aws_s3_bucket.app_bundle.id

  versioning_configuration {
    status = "Enabled"
  }
}

# ── Application Source Bundle ─────────────────────────────────────────────────

data "archive_file" "app_bundle" {
  type        = "zip"
  source_dir  = "${path.module}/../blacklist_app"
  output_path = "${path.module}/app_bundle.zip"
  excludes = [
    "docker-compose.yml",
    ".env",
    "__pycache__",
    ".pytest_cache",
  ]
}

resource "aws_s3_object" "app_bundle" {
  bucket = aws_s3_bucket.app_bundle.id
  key    = "versions/${var.app_version}/app.zip"
  source = data.archive_file.app_bundle.output_path
  etag   = data.archive_file.app_bundle.output_md5

  tags = merge(local.tags, { Version = var.app_version })
}
