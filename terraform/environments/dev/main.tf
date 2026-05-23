# ──────────────────────────────────────────────────────────────────────────
# dev environment — composes the modules: network, ecr, github-oidc,
# ec2-k3s, monitoring.
#
# Apply order is derived from Terraform's dependency graph:
#   network → ecr + github-oidc (parallel) → ec2-k3s → monitoring
# ──────────────────────────────────────────────────────────────────────────

module "network" {
  source = "../../modules/network"

  name               = var.name_prefix
  vpc_cidr           = "10.0.0.0/16"
  public_subnet_cidrs = ["10.0.0.0/24", "10.0.1.0/24"]
  availability_zones = ["${var.region}a", "${var.region}b"]

  tags = { Component = "network" }
}

module "ecr" {
  source = "../../modules/ecr"

  repository_name      = "${var.name_prefix}-nodejs"
  image_tag_mutability = "MUTABLE"
  scan_on_push         = true
  max_image_count      = 10
  tags = { Component = "registry" }
}

module "github_oidc" {
  source = "../../modules/github-oidc"

  github_owner       = var.github_owner
  github_repo        = var.github_repo
  allowed_branches   = var.allowed_branches
  ecr_repository_arn   = module.ecr.repository_arn
  role_name            = "${var.name_prefix}-gha-deploy"
  allowed_environments = var.allowed_environments
  tags = { Component = "ci" }
}

module "k3s" {
  count  = var.enable_ec2_k3s ? 1 : 0
  source = "../../modules/ec2-k3s"
  runner_labels = var.runner_labels

  name          = "${var.name_prefix}-k3s"
  instance_type = var.instance_type

  # Custom network (no default VPC).
  vpc_id    = module.network.vpc_id
  subnet_id = module.network.public_subnet_ids[0] # AZ-a; ADR-004 explains single-AZ choice.

  github_owner = var.github_owner
  github_repo  = var.github_repo
  github_token = var.github_token   # registers the self-hosted runner at boot

  # Multi-environment: this environment tracks `develop` and applies the
  # `dev` overlay at first boot. Override via terraform.tfvars if needed.
  git_branch        = var.git_branch
  kustomize_overlay = var.kustomize_overlay

  # Default to "<ecr_repo>:latest" if no specific tag was passed in.
  image_ref               = var.image_ref != "" ? var.image_ref : "${module.ecr.repository_url}:latest"
  aws_region              = var.region
  public_host             = ""
  cloudwatch_agent_config = true

  # Let's Encrypt — see ADR-008. Only the prod overlay's Ingress consumes
  # the issuer; dev/local stay self-signed. Falls back to alarm_email if
  # letsencrypt_email isn't set explicitly.
  enable_letsencrypt = var.enable_letsencrypt
  letsencrypt_email  = coalesce(var.letsencrypt_email != "" ? var.letsencrypt_email : null, var.alarm_email != "" ? var.alarm_email : null, "devops-notify@example.com")

  # Tags used by the CI pipeline to locate the instance via SSM (filters by
  # Component=runtime AND Project=<repo-name>).
  tags = {
    Component = "runtime"
    Project   = var.github_repo
  }
}

module "monitoring" {
  count  = (var.enable_ec2_k3s && var.enable_monitoring) ? 1 : 0
  source = "../../modules/monitoring"

  name        = var.name_prefix
  alarm_email = var.alarm_email
  instance_id = module.k3s[0].instance_id

  cpu_threshold_percent    = 80
  memory_threshold_percent = 85
  disk_threshold_percent   = 80
  enable_memory_disk_alarms = true

  tags = { Component = "observability" }
}
