locals {
  environments = ["dev", "prod"]
}

resource "aws_iam_role" "lambda_exec" {
  for_each = toset(local.environments)
  name     = "${var.project_name}-${each.key}-lambda-exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_logs" {
  for_each   = toset(local.environments)
  role       = aws_iam_role.lambda_exec[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "lambda_secret_access" {
  for_each = toset(local.environments)

  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.app_config[each.key].arn]
  }
}

resource "aws_iam_role_policy" "lambda_secret_access" {
  for_each = toset(local.environments)
  name     = "${var.project_name}-${each.key}-secret-read"
  role     = aws_iam_role.lambda_exec[each.key].id
  policy   = data.aws_iam_policy_document.lambda_secret_access[each.key].json
}

resource "aws_lambda_function" "app" {
  for_each      = toset(local.environments)
  function_name = "${var.project_name}-${each.key}"
  role          = aws_iam_role.lambda_exec[each.key].arn
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.app.repository_url}:${each.key}-bootstrap"
  timeout       = 10
  memory_size   = 256

  environment {
    variables = {
      APP_ENV        = each.key
      APP_SECRET_ARN = aws_secretsmanager_secret.app_config[each.key].arn
    }
  }

  lifecycle {
    ignore_changes = [image_uri]
  }
}

resource "aws_secretsmanager_secret" "app_config" {
  for_each                = toset(local.environments)
  name                    = "${var.project_name}/${each.key}/app-config"
  description             = "Environment-specific config/secrets for ${each.key}, injected at runtime (never stored in the pipeline)."
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "app_config" {
  for_each      = toset(local.environments)
  secret_id     = aws_secretsmanager_secret.app_config[each.key].id
  secret_string = jsonencode({ example_api_key = "replace-me-manually-or-via-secure-pipeline" })

  lifecycle {
    ignore_changes = [secret_string]
  }
}
