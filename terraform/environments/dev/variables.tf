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
  default     = ["main", "develop"]
}

# ─── Multi-environment knobs ──────────────────────────────────────────────
# The dev environment tracks the `develop` branch and applies the `dev`
# overlay at first boot. A future `prod` environment would override these
# back to `main` / `prod`.
variable "git_branch" {
  description = "Branch cloned by the k3s user-data on first boot. The dev environment defaults to `develop`."
  type        = string
  default     = "develop"
}

variable "kustomize_overlay" {
  description = "Kustomize overlay applied by the k3s user-data on first boot. The dev environment defaults to `dev` (so the `demo-devops-dev` namespace is created)."
  type        = string
  default     = "dev"
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

variable "enable_monitoring" {
  description = "Create the monitoring module (CloudWatch alarms + SNS). Turn off to save RAM on t3.micro or if you don't want to receive alerts."
  type        = bool
  default     = true
}

variable "allowed_environments" {
  description = "GitHub Environments allowed to assume the role via OIDC (deploy job)."
  type        = list(string)
  default     = ["dev", "production"]
}

# ─── Self-hosted GitHub Actions runner ────────────────────────────────────
variable "github_token" {
  description = "Fine-grained PAT with `Administration: read+write` on the repo. Injected into the EC2 user-data to register the self-hosted runner consumed by the workflow's `deploy` job. Leave empty to skip runner installation (the cluster still works, but the CI/CD `deploy` job will fail because there is no runner)."
  type        = string
  default     = ""
  sensitive   = true
}

variable "instance_type" {
  description = "EC2 instance type. t3.micro / t2.micro are AWS Free Tier eligible (on-demand only — Spot is NOT Free Tier)."
  type        = string
  default     = "t3.micro"
}

variable "spot_instance_types" {
  description = "Instance types the ASG is allowed to launch as Spot. Diversifying across types reduces the chance that a single-pool capacity shortage drops the node."
  type        = list(string)
  default     = ["t3.medium"]
}

# ─── TLS (Let's Encrypt on prod overlay only) ─────────────────────────────
variable "enable_letsencrypt" {
  description = "Install cert-manager + Let's Encrypt ClusterIssuers on the cluster. Only the `prod` overlay's Ingress consumes them — dev/local stay on traefik's self-signed cert (see ADR-008)."
  type        = bool
  default     = true
}

variable "letsencrypt_email" {
  description = "Contact email used by the Let's Encrypt ACME account for expiry notifications. Defaults to alarm_email when blank."
  type        = string
  default     = ""
}

variable "runner_labels" {
  description = "Labels of the self-hosted runner."
  type        = string
  default     = "self-hosted,linux,x64,k3s-deploy,k3s-dev"
}

variable "create_oidc_provider" {
  description = "Create the GitHub OIDC provider in IAM. Only one is allowed per AWS account, so the dev environment creates it (true) and prod reuses it (false)."
  type        = bool
  default     = true
}