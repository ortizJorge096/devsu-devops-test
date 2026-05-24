# ──────────────────────────────────────────────────────────────────────────
# Bootstrap module — creates the S3 bucket that holds the remote state
# for every other Terraform configuration in this repo.
#
# This module itself uses LOCAL state (terraform.tfstate in this dir),
# because there's a chicken-and-egg problem: it's creating the backend.
# Apply it ONCE, commit nothing sensitive, then the rest of the configs
# use this bucket as their backend with `use_lockfile = true`
# (Terraform 1.10+ native S3 locking — no DynamoDB needed).
#
# Free Tier note:
#   - S3:           5 GB storage + 20k GET + 2k PUT free/month for 12 months.
#                   A state file for this project is < 1 MB. Comfortably free.
#   - No DynamoDB:  removed thanks to use_lockfile (TF 1.10+).
# ──────────────────────────────────────────────────────────────────────────

resource "aws_s3_bucket" "tfstate" {
  bucket = var.state_bucket_name

  # Safety: don't let `terraform destroy` blow away years of state history.
  lifecycle {
    prevent_destroy = true
  }
}

# Versioning — required so state rollbacks are possible after a bad apply.
resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Encrypt state at rest with SSE-S3 (free, AWS-managed key).
resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block all public access — state files leak credentials if exposed.
resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle: expire noncurrent versions after 90 days to cap storage.
resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}
