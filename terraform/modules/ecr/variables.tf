variable "repository_name" {
  description = "Name of the ECR repository (e.g. demo-devops-nodejs)."
  type        = string
}

variable "image_tag_mutability" {
  description = "MUTABLE | IMMUTABLE. IMMUTABLE prevents tag overwrites (recommended for prod tags)."
  type        = string
  default     = "IMMUTABLE"
  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be MUTABLE or IMMUTABLE."
  }
}

variable "scan_on_push" {
  description = "Enable native ECR vulnerability scanning on every push (free)."
  type        = bool
  default     = true
}

variable "max_image_count" {
  description = "Lifecycle policy: number of images to keep before expiring untagged ones."
  type        = number
  default     = 10
}

variable "tags" {
  description = "Extra tags to add to the repository."
  type        = map(string)
  default     = {}
}
