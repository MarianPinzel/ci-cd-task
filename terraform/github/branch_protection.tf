resource "github_branch_protection" "main" {
  repository_id = github_repository.this.node_id
  pattern       = "main"

  required_status_checks {
    strict   = true
    contexts = ["build-and-test", "security-scan"]
  }

  required_pull_request_reviews {
    required_approving_review_count = 1
    dismiss_stale_reviews           = true
  }

  enforce_admins   = false
  allows_deletions = false
}

resource "github_repository_collaborators" "this" {
  count      = length(var.collaborators) > 0 ? 1 : 0
  repository = github_repository.this.name

  dynamic "user" {
    for_each = var.collaborators
    content {
      username   = user.key
      permission = user.value
    }
  }
}
