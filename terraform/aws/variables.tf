variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "eu-central-1"
}

variable "project_name" {
  description = "Short name used to prefix resources"
  type        = string
  default     = "ci-cd-task"
}

variable "github_org" {
  description = "GitHub organization or user that owns the repository"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name (without org/user prefix)"
  type        = string
}

variable "github_owner_id" {
  description = "Numeric GitHub user/org ID (GET /users/<login> -> id). GitHub's OIDC sub claim is scoped by this immutable ID, not just the login name, so it must match exactly."
  type        = string
}

variable "github_repo_id" {
  description = "Numeric GitHub repository ID (GET /repos/<owner>/<repo> -> id). Same reasoning as github_owner_id."
  type        = string
}
