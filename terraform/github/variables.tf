variable "github_token" {
  description = "GitHub PAT with repo/admin scope. Pass via TF_VAR_github_token env var - never commit it."
  type        = string
  sensitive   = true
}

variable "github_owner" {
  description = "GitHub org or username that will own the repository"
  type        = string
}

variable "repo_name" {
  description = "Name of the repository to create/manage"
  type        = string
  default     = "ci-cd-task"
}

variable "repo_visibility" {
  description = "public repos get GitHub secret/code scanning for free; private repos need GitHub Advanced Security for those features"
  type        = string
  default     = "public"
}

variable "production_reviewers" {
  description = "GitHub usernames or team slugs required to approve deployments to the production environment (manual approval gate)"
  type        = list(string)
  default     = []
}

variable "collaborators" {
  description = "RBAC: map of GitHub username => permission (pull, triage, push, maintain, admin)"
  type        = map(string)
  default     = {}
}

variable "aws_github_actions_role_arn" {
  description = "Output of terraform/aws (github_actions_role_arn) - stored as a repo variable, not a secret, since it is not sensitive on its own (OIDC trust policy restricts who can assume it)"
  type        = string
  default     = ""
}

variable "aws_region" {
  type    = string
  default = "eu-central-1"
}

variable "ecr_repository_url" {
  type    = string
  default = ""
}

variable "ecs_cluster_name" {
  type    = string
  default = ""
}
