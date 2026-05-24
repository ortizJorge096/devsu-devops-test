variable "region" {
  description = "AWS region for the state bucket. Pick one with Free Tier coverage."
  type        = string
  default     = "us-east-1"
}

variable "state_bucket_name" {
  description = <<-EOT
    Globally unique S3 bucket name for Terraform remote state.
    Suggestion: "devsu-devops-tfstate-<your-account-id>".
  EOT
  type        = string
}
