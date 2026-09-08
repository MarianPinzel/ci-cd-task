resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

data "aws_iam_policy_document" "github_actions_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_org}@${var.github_owner_id}/${var.github_repo}@${var.github_repo_id}:ref:refs/heads/main",
        "repo:${var.github_org}@${var.github_owner_id}/${var.github_repo}@${var.github_repo_id}:pull_request",
        "repo:${var.github_org}@${var.github_owner_id}/${var.github_repo}@${var.github_repo_id}:environment:dev",
        "repo:${var.github_org}@${var.github_owner_id}/${var.github_repo}@${var.github_repo_id}:environment:production",
      ]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name                 = "${var.project_name}-github-actions"
  assume_role_policy   = data.aws_iam_policy_document.github_actions_trust.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "github_actions_permissions" {
  statement {
    sid       = "EcrAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "EcrPushPull"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImageScanFindings",
      "ecr:DescribeImages",
    ]
    resources = [aws_ecr_repository.app.arn]
  }

  statement {
    sid    = "EcsRegisterTaskDefinition"
    effect = "Allow"
    actions = [
      "ecs:RegisterTaskDefinition",
      "ecs:DescribeTaskDefinition",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "EcsDeployService"
    effect = "Allow"
    actions = [
      "ecs:UpdateService",
      "ecs:DescribeServices",
    ]
    resources = [
      "arn:aws:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:service/${aws_ecs_cluster.this.name}/${aws_ecs_service.app["dev"].name}",
      "arn:aws:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:service/${aws_ecs_cluster.this.name}/${aws_ecs_service.app["prod"].name}",
    ]
  }

  statement {
    sid    = "EcsSmokeTestLookup"
    effect = "Allow"
    actions = [
      "ecs:ListTasks",
      "ecs:DescribeTasks",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "PassEcsTaskRoles"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = concat(values(aws_iam_role.ecs_execution)[*].arn, values(aws_iam_role.ecs_task)[*].arn)

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }

  statement {
    sid       = "SmokeTestNetworkLookup"
    effect    = "Allow"
    actions   = ["ec2:DescribeNetworkInterfaces"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "github_actions_permissions" {
  name   = "${var.project_name}-github-actions-deploy"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.github_actions_permissions.json
}
