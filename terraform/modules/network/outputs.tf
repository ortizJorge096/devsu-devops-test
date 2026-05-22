output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "List of public subnet IDs, in AZ order."
  value       = aws_subnet.public[*].id
}

output "availability_zones" {
  description = "AZs where public subnets live."
  value       = var.availability_zones
}

output "internet_gateway_id" {
  description = "ID of the IGW."
  value       = aws_internet_gateway.this.id
}
