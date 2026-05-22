variable "github_owner" {
  description = "GitHub user/org that owns the repository (e.g. ortizJorge096)."
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name (e.g. devsu-devops-test)."
  type        = string
}

variable "allowed_branches" {
  description = "List of branches/tags allowed to assume the role (e.g. [\"main\"])."
  type        = list(string)
  default     = ["main", "develop"]
}

variable "ecr_repository_arn" {
  description = "ARN of the ECR repo the role can push to."
  type        = string
}

variable "role_name" {
  description = "Name for the IAM role assumed by GitHub Actions."
  type        = string
  default     = "github-actions-devsu-deploy"
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}

variable "allowed_environments" {
  description = "GitHub Environments allowed to assume the role via OIDC (e.g. [\"dev\", \"production\"])."
  type        = list(string)
  default     = []
}
