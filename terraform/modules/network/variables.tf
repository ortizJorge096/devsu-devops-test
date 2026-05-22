variable "name" {
  description = "Name prefix used to tag every resource (e.g. devsu-devops)."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "List of CIDRs for public subnets — one per AZ. Length must match availability_zones."
  type        = list(string)
  default     = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "availability_zones" {
  description = "AZs to deploy subnets into. 2 AZs is the minimum for any future migration to ASG/EKS multi-AZ."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "tags" {
  description = "Extra tags to merge."
  type        = map(string)
  default     = {}
}
