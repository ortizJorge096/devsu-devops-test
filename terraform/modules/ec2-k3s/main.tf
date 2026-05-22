# ──────────────────────────────────────────────────────────────────────────
# Single-node k3s cluster on an EC2 t3.micro (AWS Free Tier).
#
# Why k3s instead of EKS?
#   - EKS control plane = ~$73/mo, NOT Free Tier.
#   - k3s is a CNCF-certified K8s distribution; perfect for demos and
#     edge workloads. Fits comfortably on a t3.micro (1 GiB RAM).
#
# What this module provisions:
#   - SG (80/HTTP, 443/HTTPS only — NO SSH; access via SSM Session Manager)
#   - IAM instance profile with:
#       * AmazonEC2ContainerRegistryReadOnly  → ECR pull via instance profile
#       * AmazonSSMManagedInstanceCore        → SSM Session Manager
#       * CloudWatchAgentServerPolicy         → publish custom metrics
#   - EC2 instance with userdata that installs k3s + CloudWatch agent
#   - Elastic IP (free while attached to a running instance)
#
# Network: the module REQUIRES vpc_id + subnet_id — no default VPC fallback.
# Single-AZ by design (see docs/decisions/ADR-004-single-az.md).
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
# Inbound: HTTP/80 + HTTPS/443 only. No SSH (port 22 NOT opened).
# Outbound: unrestricted (needed for: ECR pull, dnf updates, GitHub clone,
# CloudWatch publish, SSM Messages).
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

# SSM Session Manager — exec into the node WITHOUT SSH or open ports.
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# CloudWatch Agent — required to publish memory/disk metrics.
resource "aws_iam_role_policy_attachment" "cw_agent" {
  count      = var.cloudwatch_agent_config ? 1 : 0
  role       = aws_iam_role.node.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "node" {
  name = "${var.name}-profile"
  role = aws_iam_role.node.name
  tags = var.tags
}

# ─── Userdata ──────────────────────────────────────────────────────────────
locals {
  userdata = templatefile("${path.module}/userdata.sh.tftpl", {
    github_owner            = var.github_owner
    github_repo             = var.github_repo
    image_ref               = var.image_ref
    aws_region              = var.aws_region
    public_host             = var.public_host
    enable_cloudwatch_agent = var.cloudwatch_agent_config
  })
}

# ─── EC2 instance ──────────────────────────────────────────────────────────
resource "aws_instance" "this" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.this.id]
  iam_instance_profile        = aws_iam_instance_profile.node.name

  user_data                   = local.userdata
  user_data_replace_on_change = true

  # IMDSv2 only — defense against SSRF-style attacks on the metadata service.
  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20      # Free Tier covers up to 30 GB EBS
    encrypted             = true
    delete_on_termination = true
  }

  tags = merge(var.tags, { Name = var.name })
}

# ─── Elastic IP (free while attached) ─────────────────────────────────────
resource "aws_eip" "this" {
  domain   = "vpc"
  instance = aws_instance.this.id
  tags     = merge(var.tags, { Name = "${var.name}-eip" })
}
