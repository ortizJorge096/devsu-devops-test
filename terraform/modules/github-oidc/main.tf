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
# AWS allows a single GitHub OIDC provider per account, so the second
# environment to apply must reuse the one created by the first. Toggle:
#   - var.create_oidc_provider = true  -> create it here (used by dev,
#     which is applied first in this repo).
#   - var.create_oidc_provider = false -> skip creation and look it up
#     via the `data` block below (used by prod, see its tfvars).
resource "aws_iam_openid_connect_provider" "github" {
  count           = var.create_oidc_provider ? 1 : 0
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

# Look up the existing provider only when we're NOT creating it here.
# Reading it unconditionally would fail with NoSuchEntity on a first
# apply in a fresh AWS account (the provider doesn't exist yet).
data "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

locals {
  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
}
# Trust policy: only GH Actions for this specific repo + listed branches.
data "aws_iam_policy_document" "trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = concat(
        # Branch-based claims (build-push, image-scan jobs)
        [
          for b in var.allowed_branches :
          "repo:${var.github_owner}/${var.github_repo}:ref:refs/heads/${b}"
        ],
        # Environment-based claims (deploy job)
        [
          for e in var.allowed_environments :
          "repo:${var.github_owner}/${var.github_repo}:environment:${e}"
        ],
        # Pull request events use a different sub format (no ref prefix)
        ["repo:${var.github_owner}/${var.github_repo}:pull_request"]
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
