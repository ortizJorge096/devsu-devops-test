# ──────────────────────────────────────────────────────────────────────────
# ECR module — the **primary** container registry for this project.
#
# CI pushes images here via OIDC + the `github-oidc` IAM role; the k3s
# node on EC2 pulls them using the instance profile (no static creds).
#
# Free Tier:
#   - Private ECR: 500 MB storage free for first 12 months. Our image
#     is ~150 MB so we have headroom. The lifecycle policy below keeps
#     the repo from growing unbounded.
# ──────────────────────────────────────────────────────────────────────────

resource "aws_ecr_repository" "this" {
  name                 = var.repository_name
  image_tag_mutability = var.image_tag_mutability
  force_delete         = false

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = var.tags
}

# Keep the repo small: expire untagged images after 7 days, and prune
# tagged ones once we exceed max_image_count (keeps the newest N).
resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only the latest ${var.max_image_count} tagged images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.max_image_count
        }
        action = { type = "expire" }
      }
    ]
  })
}
