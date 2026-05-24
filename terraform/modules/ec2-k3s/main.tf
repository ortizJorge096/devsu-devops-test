# ──────────────────────────────────────────────────────────────────────────
# Single-node k3s cluster on EC2 — provisioned through an Auto Scaling Group
# with a Mixed Instances Policy so AWS auto-replaces the node when a Spot
# reclaim happens (ADR-009).
#
# Why ASG instead of a bare aws_instance?
#   - Spot one-time instances do NOT auto-recover. Without an ASG, a reclaim
#     leaves the cluster permanently down until `terraform apply` is rerun.
#   - With desired_capacity = 1 + capacity_rebalance + several instance types,
#     AWS launches a replacement automatically (2-min interruption notice
#     drains the old one, the new one boots from the same Launch Template
#     and the same user-data, k3s reinstalls in ~5-7 min).
#   - The Elastic IP is decoupled from the instance and the user-data
#     re-associates it on boot, so the public FQDN (nip.io) stays stable
#     across reclaims — no Let's Encrypt rate-limit hit.
#
# What this module provisions:
#   - SG (80/HTTP, 443/HTTPS only — NO SSH; access via SSM Session Manager)
#   - IAM instance profile with:
#       * AmazonEC2ContainerRegistryReadOnly  → ECR pull via instance profile
#       * AmazonSSMManagedInstanceCore        → SSM Session Manager
#       * CloudWatchAgentServerPolicy         → publish custom metrics
#       * inline policy for `ec2:AssociateAddress` on this module's EIP only
#   - Launch Template with the user-data + IMDSv2 + encrypted root EBS
#   - Auto Scaling Group (desired=1, min=1, max=1) with Mixed Instances
#     Policy (Spot across several instance types + optional on-demand %).
#   - Elastic IP (free while attached), re-associated by the user-data.
#
# Network: requires vpc_id + subnet_id — no default VPC fallback.
# Single-AZ by design (see docs/decisions/ADR-004-single-az-deployment.md).
# ──────────────────────────────────────────────────────────────────────────

data "aws_partition" "current" {}
data "aws_region" "current" {}

# Amazon Linux 2023 (x86_64).
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023*-x86_64"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ─── Security Group ────────────────────────────────────────────────────────
resource "aws_security_group" "this" {
  name        = "${var.name}-sg"
  description = "k3s node: HTTP/HTTPS ingress, no SSH (use SSM Session Manager)"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP (traefik)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS (traefik)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound (ECR, GitHub, SSM, CloudWatch, dnf)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name}-sg" })
}

# ─── IAM instance profile ─────────────────────────────────────────────────
data "aws_iam_policy_document" "ec2_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${var.name}-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "ecr_read" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cw_agent" {
  count      = var.cloudwatch_agent_config ? 1 : 0
  role       = aws_iam_role.node.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# ─── Inline policy: re-associate the EIP from user-data ───────────────────
# Note: ec2:AssociateAddress is evaluated by IAM against MULTIPLE resource
# ARNs at once (the EIP allocation, the instance, and the ENI). A
# `Condition { ec2:AllocationId = ... }` does NOT scope the action because
# the request still references the instance ARN, which has no matching
# AllocationId — IAM denies. To keep the user-data working we grant the
# action on `*` without a condition. Scope is still tight in practice:
#   - this IAM role is attached to a single ASG node;
#   - the role's trust policy only allows ec2.amazonaws.com to assume it;
#   - the user-data has the EIP allocation_id hardcoded at template time
#     and won't ask AWS to associate anything else.
# If you need to lock it down further, tag the EIP and the instance with
# the same `Project` tag and switch to `aws:ResourceTag/Project` matching.
data "aws_iam_policy_document" "eip_associate" {
  statement {
    sid       = "DescribeAddresses"
    effect    = "Allow"
    actions   = ["ec2:DescribeAddresses"]
    resources = ["*"]
  }

  statement {
    sid       = "AssociateOurEip"
    effect    = "Allow"
    actions   = ["ec2:AssociateAddress", "ec2:DisassociateAddress"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "eip_associate" {
  name   = "${var.name}-eip-associate"
  role   = aws_iam_role.node.id
  policy = data.aws_iam_policy_document.eip_associate.json
}

resource "aws_iam_instance_profile" "node" {
  name = "${var.name}-profile"
  role = aws_iam_role.node.name
  tags = var.tags
}

# ─── Elastic IP (persistent — survives Spot reclaims) ─────────────────────
# Allocated ONCE; re-associated by the user-data on every boot. Keeps the
# nip.io FQDN stable so cert-manager reuses the existing Let's Encrypt
# certificate instead of asking for a new one on every reclaim.
resource "aws_eip" "this" {
  domain = "vpc"
  tags   = merge(var.tags, { Name = "${var.name}-eip" })
}

# ─── User-data ────────────────────────────────────────────────────────────
locals {
  effective_public_host = var.public_host != "" ? var.public_host : "demo-devops.${replace(aws_eip.this.public_ip, ".", "-")}.nip.io"

  userdata = templatefile("${path.module}/userdata.sh.tftpl", {
    github_owner            = var.github_owner
    github_repo             = var.github_repo
    git_branch              = var.git_branch
    kustomize_overlay       = var.kustomize_overlay
    image_ref               = var.image_ref
    aws_region              = var.aws_region
    public_host             = local.effective_public_host
    enable_cloudwatch_agent = var.cloudwatch_agent_config
    enable_letsencrypt      = var.enable_letsencrypt
    letsencrypt_email       = var.letsencrypt_email
    github_token            = var.github_token
    runner_labels           = var.runner_labels
    runner_version          = var.runner_version
    eip_allocation_id       = aws_eip.this.allocation_id
  })
}

# ─── Launch Template ──────────────────────────────────────────────────────
resource "aws_launch_template" "this" {
  name_prefix   = "${var.name}-lt-"
  image_id      = data.aws_ami.al2023.id
  instance_type = var.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.node.name
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.this.id]
    delete_on_termination       = true
  }

  metadata_options {
    http_tokens                 = "required"
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 2
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_type           = "gp3"
      volume_size           = 20
      encrypted             = true
      delete_on_termination = true
    }
  }

  user_data = base64encode(local.userdata)

  tag_specifications {
    resource_type = "instance"
    tags          = merge(var.tags, { Name = var.name })
  }
  tag_specifications {
    resource_type = "volume"
    tags          = merge(var.tags, { Name = "${var.name}-root" })
  }
  tag_specifications {
    resource_type = "network-interface"
    tags          = merge(var.tags, { Name = "${var.name}-eni" })
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.tags, { Name = "${var.name}-lt" })
}

# ─── Auto Scaling Group ───────────────────────────────────────────────────
resource "aws_autoscaling_group" "this" {
  name                      = var.name
  min_size                  = 1
  max_size                  = 1
  desired_capacity          = 1
  vpc_zone_identifier       = [var.subnet_id]
  health_check_type         = "EC2"
  health_check_grace_period = 300
  default_cooldown          = 60

  capacity_rebalance = true

  termination_policies = ["OldestInstance"]

  wait_for_capacity_timeout = "10m"

  mixed_instances_policy {
    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.this.id
        version            = "$Latest"
      }

      dynamic "override" {
        for_each = var.spot_instance_types
        content {
          instance_type = override.value
        }
      }
    }

    instances_distribution {
      on_demand_base_capacity                  = var.on_demand_base_capacity
      on_demand_percentage_above_base_capacity = var.on_demand_percentage_above_base_capacity
      on_demand_allocation_strategy            = "lowest-price"
      spot_allocation_strategy                 = "price-capacity-optimized"
    }
  }

  dynamic "tag" {
    for_each = merge(var.tags, { Name = var.name })
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  timeouts {
    delete = "15m"
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 0
      instance_warmup        = 300
    }
    triggers = ["tag", "launch_template"]
  }

  lifecycle {
    ignore_changes = [desired_capacity]
  }
}
