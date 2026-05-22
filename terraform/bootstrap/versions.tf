terraform {
  # >= 1.10 unlocks the S3 native state-locking feature (use_lockfile = true),
  # so we no longer need a DynamoDB lock table — fewer moving parts and
  # cheaper to keep inside AWS Free Tier limits.
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project     = "devsu-devops-test"
      Environment = "shared"
      ManagedBy   = "terraform"
      Component   = "bootstrap"
    }
  }
}
