output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

output "github_actions_role_arn" {
  description = "Set this as the AWS_ROLE_ARN variable in GitHub (used by the CD workflow via OIDC)"
  value       = aws_iam_role.github_actions.arn
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.this.name
}

output "ecs_service_names" {
  value = { for env, svc in aws_ecs_service.app : env => svc.name }
}
