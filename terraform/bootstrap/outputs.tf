output "state_bucket_name" {
  description = "S3 bucket holding the remote Terraform state."
  value       = aws_s3_bucket.tfstate.bucket
}

output "state_bucket_arn" {
  description = "ARN of the state bucket — pass to least-privilege IAM policies."
  value       = aws_s3_bucket.tfstate.arn
}

output "region" {
  description = "AWS region of the state bucket."
  value       = var.region
}

output "backend_snippet" {
  description = "Copy this into each environment's backend.tf."
  value       = <<-EOT
    terraform {
      backend "s3" {
        bucket       = "${aws_s3_bucket.tfstate.bucket}"
        key          = "<env>/terraform.tfstate"
        region       = "${var.region}"
        encrypt      = true
        use_lockfile = true     # native S3 locking (Terraform >= 1.10)
      }
    }
  EOT
}
