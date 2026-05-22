variable "region" {
  description = "AWS region — pick a Free Tier covered one (e.g. us-east-1)."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix applied to most resources."
  type        = string
  default     = "devsu-devops"
}

# ─── GitHub identity (OIDC + manifests source) ─────────────────────────────
variable "github_owner" {
  description = "GitHub owner (e.g. ortizJorge096)."
  type        = string
}

variable "github_repo" {
  description = "GitHub repo name (e.g. devsu-devops-test)."
  type        = string
}

variable "allowed_branches" {
  description = "Branches allowed to assume the AWS role via OIDC."
  type        = list(string)
  default     = ["main"]
}

# ─── EC2 / k3s ─────────────────────────────────────────────────────────────
variable "image_ref" {
  description = "Full ECR image to deploy (e.g. 123.dkr.ecr.us-east-1.amazonaws.com/devsu-devops-nodejs:sha-abc1234). Defaults to <repo>:latest if blank."
  type        = string
  default     = ""
}

variable "enable_ec2_k3s" {
  description = "Create the EC2 + k3s cluster (true) or skip it (false)."
  type        = bool
  default     = true
}

# ─── Monitoring ────────────────────────────────────────────────────────────
variable "alarm_email" {
  description = "Email that receives CloudWatch alarm notifications. AWS sends a confirmation email — click the link before alarms can publish to you. Leave blank to skip the subscription."
  type        = string
  default     = ""
}

variable "allowed_environments" {
  description = "GitHub Environments allowed to assume the role via OIDC (deploy job)."
  type        = list(string)
  default     = ["dev", "production"]
}
