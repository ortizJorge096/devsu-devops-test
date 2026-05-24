# ──────────────────────────────────────────────────────────────────────────
# Network module — VPC with public subnets across multiple AZs.
#
# Topology:
#   - 1 VPC (10.0.0.0/16)
#   - 2 public subnets, one per AZ (us-east-1a, us-east-1b)
#   - 1 Internet Gateway
#   - 1 public route table associated with both subnets
#
# What is INTENTIONALLY left out (to stay inside AWS Free Tier):
#   - NAT gateway: costs ~$32/mo + data transfer. No private subnets means
#     no need for NAT. If we add private subnets later, we'd either pay
#     for NAT or use a NAT instance on t3.micro.
#   - Private subnets: not provisioned because nothing currently runs in
#     them. Easy to add via `var.private_subnet_cidrs` if needed.
#   - VPC Flow Logs to CloudWatch / S3: $0.50/GB ingested in CloudWatch.
#     Enable in production for forensics; off here to keep Free Tier clean.
# ──────────────────────────────────────────────────────────────────────────

locals {
  az_count = length(var.availability_zones)
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, {
    Name = "${var.name}-vpc"
  })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name}-igw"
  })
}

resource "aws_subnet" "public" {
  count                   = local.az_count
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name = "${var.name}-public-${var.availability_zones[count.index]}"
    Tier = "public"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(var.tags, {
    Name = "${var.name}-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  count          = local.az_count
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Default Security Group of the VPC: lock it down to nothing (best practice).
# Anything that needs network access must use a purpose-built SG (like the
# ec2-k3s module creates).
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  # No ingress, no egress — the default SG should be a black hole.

  tags = merge(var.tags, {
    Name = "${var.name}-default-sg-locked"
  })
}
