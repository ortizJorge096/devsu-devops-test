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

variable "cloudwatch_agent_config" {
  description = "Whether to install + configure CloudWatch Agent for memory/disk metrics."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}

# ─── Self-hosted GitHub Actions runner ────────────────────────────────────
variable "github_token" {
  description = "PAT fine-grained con Administration: read+write sobre el repo (o classic con scope `repo`). Sólo se usa en user-data para obtener un registration-token efímero. Dejar vacío omite la instalación del runner."
  type        = string
  default     = ""
  sensitive   = true
}

variable "runner_labels" {
  description = "Labels del self-hosted runner. El workflow apunta a `k3s-deploy`."
  type        = string
  default     = "self-hosted,linux,x64,k3s-deploy"
}

variable "runner_version" {
  description = "Versión del actions/runner a instalar."
  type        = string
  default     = "2.319.1"
}
