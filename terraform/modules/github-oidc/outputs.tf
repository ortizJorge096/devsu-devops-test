output "role_arn" {
  description = "ARN of the IAM role GitHub Actions should assume (set as AWS_ROLE_ARN secret)."
  value       = aws_iam_role.github.arn
}

output "role_name" {
  description = "Name of the IAM role."
  value       = aws_iam_role.github.name
}

output "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider for GitHub Actions."
  value       = local.oidc_provider_arn
}
