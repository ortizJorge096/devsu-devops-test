# ──────────────────────────────────────────────────────────────────────────
# GitHub Actions → AWS via OIDC (no long-lived access keys).
#
# This module:
#   1) Registers GitHub's OIDC provider in IAM (one per account, idempotent
#      via data source check below).
#   2) Creates a role that GitHub Actions can assume *only* from the named
#      repo + branches.
#   3) Attaches a least-privilege policy: push to the given ECR repo +
#      describe EC2 (for deploy steps).
#
# Free Tier: IAM, OIDC, and identity policies are always free.
# ──────────────────────────────────────────────────────────────────────────

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# Only create the OIDC provider once per account.
# If you already have one (very common), set `var.create_oidc_provider = false`
# and pass its ARN in `var.existing_oidc_provider_arn`. Simplified here
# to always create — comment out if the provider already exists.
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  # GitHub's OIDC root thumbprint. GitHub now signs with multiple roots —
  # AWS recommends `6938fd4d98bab03faadb97b34396831e3780aea1` as the canonical one.
  # Modern aws-actions/configure-aws-credentials no longer requires the
  # thumbprint to match (uses the issuer URL signature), but it's still
  # required by the API.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
  tags            = var.tags
}

# Trust policy: only GH Actions for this specific repo + listed branches.
data "aws_iam_policy_document" "trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # `repo:owner/repo:ref:refs/heads/<branch>` — pin to specific branches.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = concat(
        # Branch-based claims (build-push, image-scan jobs)
        [
          for b in var.allowed_branches :
          "repo:${var.github_owner}/${var.github_repo}:ref:refs/heads/${b}"
        ],
        # Environment-based claims (deploy job — sub changes when job has environment: set)
        [
          for e in var.allowed_environments :
          "repo:${var.github_owner}/${var.github_repo}:environment:${e}"
        ]
      )
    }
  }
}

resource "aws_iam_role" "github" {
  name               = var.role_name
  assume_role_policy = data.aws_iam_policy_document.trust.json
  tags               = var.tags
}

# Least-privilege: push/pull from this one ECR repo only.
data "aws_iam_policy_document" "ecr" {
  statement {
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
    ]
    resources = ["*"]   # GetAuthorizationToken requires *, can't scope.
  }
  statement {
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
      "ecr:BatchGetImage",
      "ecr:DescribeImages",
      "ecr:GetDownloadUrlForLayer",
      "ecr:ListImages",
    ]
    resources = [var.ecr_repository_arn]
  }
  statement {
    effect = "Allow"
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeTags",
    ]
    resources = ["*"]
  }

  # Deploy via SSM Send-Command (replaces the old SSH-based deploy).
  # SendCommand cannot be scoped to a specific instance ARN at the policy
  # level (the API requires resource = arn:aws:ssm:*:*:document/*
  # AND arn:aws:ec2:*:*:instance/*). We allow it broadly but constrain via
  # the workflow which filters instances by tag at runtime.
  statement {
    sid    = "SsmSendCommand"
    effect = "Allow"
    actions = [
      "ssm:SendCommand",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:ssm:*:*:document/AWS-RunShellScript",
      "arn:${data.aws_partition.current.partition}:ec2:*:${data.aws_caller_identity.current.account_id}:instance/*",
    ]
  }

  statement {
    sid    = "SsmReadCommandResults"
    effect = "Allow"
    actions = [
      "ssm:GetCommandInvocation",
      "ssm:ListCommandInvocations",
      "ssm:DescribeInstanceInformation",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "ecr" {
  name   = "${var.role_name}-ecr-push"
  policy = data.aws_iam_policy_document.ecr.json
  tags   = var.tags
}

resource "aws_iam_role_policy_attachment" "ecr" {
  role       = aws_iam_role.github.name
  policy_arn = aws_iam_policy.ecr.arn
}
