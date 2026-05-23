terraform {
  # Remote state backed by the S3 bucket created in terraform/bootstrap.
  # `use_lockfile = true` is the Terraform >= 1.10 native S3 locking
  # mechanism — drops the DynamoDB requirement entirely.
  #
  # After `terraform/bootstrap` is applied, replace the bucket name below
  # (or pass it via `terraform init -backend-config=...`).
  backend "s3" {
    bucket       = "devsu-devops-test-tfstate"
    key          = "prod/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
