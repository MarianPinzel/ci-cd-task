terraform {
  required_version = ">= 1.5.0"

  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }
}

provider "github" {
  owner = var.github_owner
  token = var.github_token
}

resource "github_repository" "this" {
  name        = var.repo_name
  description = "Demo repo: CI/CD from scratch with security controls (GitHub Actions + Terraform + AWS)."
  visibility  = var.repo_visibility

  has_issues   = true
  has_wiki     = false
  has_projects = false
  auto_init    = true

  security_and_analysis {
    secret_scanning {
      status = "enabled"
    }
    secret_scanning_push_protection {
      status = "enabled"
    }
  }

  delete_branch_on_merge = true
}

# Dependency/CVE alerts (Dependabot alerts) - dedicated resource, the
# github_repository.vulnerability_alerts field is deprecated.
resource "github_repository_vulnerability_alerts" "this" {
  repository = github_repository.this.name
  enabled    = true
}
