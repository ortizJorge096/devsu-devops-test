variable "name" {
  description = "Name prefix for resources (e.g. devsu-devops-k3s)."
  type        = string
  default     = "devsu-k3s"
}

variable "vpc_id" {
  description = "ID of the VPC where the SG and EC2 will live."
  type        = string
}

variable "subnet_id" {
  description = "ID of the public subnet where instances will be launched."
  type        = string
}

variable "instance_type" {
  description = "Default EC2 instance type baked into the launch template. The ASG mixed_instances_policy overrides it per pool."
  type        = string
  default     = "t3.micro"
}

# ─── Spot / ASG ───────────────────────────────────────────────────────────
variable "spot_instance_types" {
  description = "Instance types the ASG is allowed to launch as Spot. Diversifying across types reduces the chance that a single-pool capacity shortage drops the node (ADR-009)."
  type        = list(string)
  default = [
    "t3.micro",
    "t3a.micro",
    "t2.micro",
    "t3.small",
    "t3a.small",
  ]
}

variable "on_demand_base_capacity" {
  description = "Minimum number of on-demand instances. Set to 1 with desired=1 to force pure on-demand (emergency switch when all Spot pools are out of capacity)."
  type        = number
  default     = 0
}

variable "on_demand_percentage_above_base_capacity" {
  description = "Percentage of capacity above on_demand_base_capacity that runs on on-demand. 0 = pure Spot above the base; 100 = all on-demand."
  type        = number
  default     = 0
  validation {
    condition     = var.on_demand_percentage_above_base_capacity >= 0 && var.on_demand_percentage_above_base_capacity <= 100
    error_message = "on_demand_percentage_above_base_capacity must be in [0, 100]."
  }
}

variable "image_ref" {
  description = "Full ECR image reference deployed to k3s."
  type        = string
}

variable "aws_region" {
  description = "AWS region for ECR + EIP re-association."
  type        = string
  default     = "us-east-1"
}

variable "public_host" {
  description = "Host for the Ingress rule. Leave blank to derive a nip.io FQDN from the EIP."
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
variable "git_branch" {
  description = "Git branch to clone in userdata for the initial bootstrap apply (main for prod, develop for dev)."
  type        = string
  default     = "main"
}

variable "kustomize_overlay" {
  description = "Kustomize overlay under k8s/overlays/ to apply at first boot."
  type        = string
  default     = "prod"
}

variable "cloudwatch_agent_config" {
  description = "Whether to install + configure CloudWatch Agent for memory/disk metrics."
  type        = bool
  default     = true
}

# ─── Let's Encrypt (cert-manager) ─────────────────────────────────────────
variable "enable_letsencrypt" {
  description = "Install cert-manager on first boot and provision Let's Encrypt ClusterIssuers (prod + staging)."
  type        = bool
  default     = false
}

variable "letsencrypt_email" {
  description = "Contact email for the Let's Encrypt ACME account."
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
  description = "Fine-grained PAT with Administration:read+write on the repo. Used in user-data only — for runner registration AND to delete stale offline runners left by previously reclaimed instances."
  type        = string
  default     = ""
  sensitive   = true
}

variable "runner_labels" {
  description = "Labels of the self-hosted runner. The CI/CD workflow targets specific labels per environment."
  type        = string
  default     = "self-hosted,linux,x64,k3s-deploy"
}

variable "runner_version" {
  description = "actions/runner version to install."
  type        = string
  default     = "2.319.1"
}
