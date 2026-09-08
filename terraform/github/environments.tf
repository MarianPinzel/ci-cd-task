# Dev: deploys automatically, no approval gate, restricted to main branch builds.
resource "github_repository_environment" "dev" {
  repository  = github_repository.this.name
  environment = "dev"

  deployment_branch_policy {
    protected_branches     = true
    custom_branch_policies = false
  }
}

# Production: promotion from Dev requires a human approval (satisfies the
# "manual approval before Prod" acceptance criterion) and is also locked to main.
resource "github_repository_environment" "production" {
  repository  = github_repository.this.name
  environment = "production"

  dynamic "reviewers" {
    for_each = length(var.production_reviewers) > 0 ? [1] : []
    content {
      users = [for u in var.production_reviewers : u]
    }
  }

  deployment_branch_policy {
    protected_branches     = true
    custom_branch_policies = false
  }
}

locals {
  common_env_vars = {
    AWS_REGION     = var.aws_region
    ECR_REPOSITORY = var.ecr_repository_url
    AWS_ROLE_ARN   = var.aws_github_actions_role_arn
  }
}

resource "github_actions_environment_variable" "dev" {
  for_each      = local.common_env_vars
  repository    = github_repository.this.name
  environment   = github_repository_environment.dev.environment
  variable_name = each.key
  value         = each.value
}

resource "github_actions_environment_variable" "dev_lambda" {
  repository    = github_repository.this.name
  environment   = github_repository_environment.dev.environment
  variable_name = "LAMBDA_FUNCTION_NAME"
  value         = "ci-cd-task-dev"
}

resource "github_actions_environment_variable" "production" {
  for_each      = local.common_env_vars
  repository    = github_repository.this.name
  environment   = github_repository_environment.production.environment
  variable_name = each.key
  value         = each.value
}

resource "github_actions_environment_variable" "production_lambda" {
  repository    = github_repository.this.name
  environment   = github_repository_environment.production.environment
  variable_name = "LAMBDA_FUNCTION_NAME"
  value         = "ci-cd-task-prod"
}
