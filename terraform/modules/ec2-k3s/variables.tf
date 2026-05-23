variable "name" {
  description = "Name prefix for resources (e.g. devsu-devops-k3s)."
  type        = string
  default     = "devsu-k3s"
}

variable "vpc_id" {
  description = "ID of the VPC where the SG and EC2 will live. Required (no default VPC fallback)."
  type        = string
}

variable "subnet_id" {
  description = "ID of the public subnet where the EC2 will be launched. Required."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type. t3.micro / t2.micro are AWS Free Tier eligible."
  type        = string
  default     = "t3.micro"
}

variable "image_ref" {
  description = "Full ECR image reference deployed to k3s (e.g. 123.dkr.ecr.us-east-1.amazonaws.com/devsu-devops-nodejs:sha-abc1234)."
  type        = string
}

variable "aws_region" {
  description = "AWS region for ECR (used by amazon-ecr-credential-helper on the node)."
  type        = string
  default     = "us-east-1"
}

variable "public_host" {
  description = "Host for the Ingress rule. Leave blank for any-host routing on traefik."
  type        = string
  default     = ""
}

variable "github_owner" {
  description = "GitHub owner that hosts the repo (cloned by userdata for manifests)."
  type        = string
}

variable "github_repo" {
  description = "GitHub repo name that hosts the manifests."
  type        = string
}

# ─── Multi-environment knobs ──────────────────────────────────────────────
# These two control what gets cloned + applied at first boot. Defaults match
# the "production" environment (main branch, prod overlay) so the module is
# safe to call without overrides. The `dev` environment overrides both.
variable "git_branch" {
  description = "Git branch to clone in userdata for the initial bootstrap apply (e.g. `main` for prod, `develop` for dev). The self-hosted runner takes over for subsequent deploys, so this only affects the first apply done by cloud-init."
  type        = string
  default     = "main"
}

variable "kustomize_overlay" {
  description = "Kustomize overlay under `k8s/overlays/` to apply at first boot (e.g. `prod`, `dev`). Must exist in the cloned repo at the branch above."
  type        = string
  default     = "prod"
}

variable "cloudwatch_agent_config" {
  description = "Whether to install + configure CloudWatch Agent for memory/disk metrics."
  type        = bool
  default     = true
}

# ─── Let's Encrypt (cert-manager) ─────────────────────────────────────────
# Adds ~80-120 MB RAM cluster-wide (cert-manager controller + webhook +
# cainjector). Only the prod overlay's Ingress consumes the issuer —
# dev/local Ingresses stay self-signed (see ADR-008).
variable "enable_letsencrypt" {
  description = "Install cert-manager on first boot and provision Let's Encrypt ClusterIssuers (prod + staging). The prod overlay's Ingress is annotated to use `letsencrypt-prod`; dev overlay stays on traefik's self-signed cert."
  type        = bool
  default     = false
}

variable "letsencrypt_email" {
  description = "Contact email for the Let's Encrypt ACME account. Required when enable_letsencrypt is true — Let's Encrypt uses it for expiry notifications. Not exposed publicly."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}

# ─── Self-hosted GitHub Actions runner ────────────────────────────────────
variable "github_token" {
  description = "Fine-grained PAT with `Administration: read+write` on the repo (or classic with `repo` scope). Used in user-data only to fetch an ephemeral runner registration-token. Leave empty to skip the runner install."
  type        = string
  default     = ""
  sensitive   = true
}

variable "runner_labels" {
  description = "Labels of the self-hosted runner. The CI/CD workflow targets the `k3s-deploy` label."
  type        = string
  default     = "self-hosted,linux,x64,k3s-deploy"
}

variable "runner_version" {
  description = "actions/runner version to install."
  type        = string
  default     = "2.319.1"
}
