terraform {
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
      Environment = "dev"
      ManagedBy   = "terraform"
      Owner       = "jcaballeroo96"
    }
  }
}
