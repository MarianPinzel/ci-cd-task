output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

output "github_actions_role_arn" {
  description = "Set this as the AWS_ROLE_ARN variable in GitHub (used by the CD workflow via OIDC)"
  value       = aws_iam_role.github_actions.arn
}

output "lambda_function_names" {
  value = { for env, fn in aws_lambda_function.app : env => fn.function_name }
}
