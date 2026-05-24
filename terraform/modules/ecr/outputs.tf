output "repository_url" {
  description = "Full ECR repository URL (use as docker image registry)."
  value       = aws_ecr_repository.this.repository_url
}

output "repository_arn" {
  description = "ECR repository ARN (for IAM policies)."
  value       = aws_ecr_repository.this.arn
}

output "repository_name" {
  description = "ECR repository name."
  value       = aws_ecr_repository.this.name
}
