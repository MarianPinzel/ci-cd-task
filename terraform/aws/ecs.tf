data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_ecs_cluster" "this" {
  name = "${var.project_name}-cluster"
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = ["FARGATE"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
  }
}

resource "aws_security_group" "app" {
  for_each    = toset(local.environments)
  name        = "${var.project_name}-${each.key}-sg"
  description = "Allow inbound app traffic for ${each.key} Fargate tasks"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_iam_role" "ecs_execution" {
  for_each = toset(local.environments)
  name     = "${var.project_name}-${each.key}-ecs-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  for_each   = toset(local.environments)
  role       = aws_iam_role.ecs_execution[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task" {
  for_each = toset(local.environments)
  name     = "${var.project_name}-${each.key}-ecs-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

data "aws_iam_policy_document" "ecs_task_secret_access" {
  for_each = toset(local.environments)

  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.app_config[each.key].arn]
  }
}

resource "aws_iam_role_policy" "ecs_task_secret_access" {
  for_each = toset(local.environments)
  name     = "${var.project_name}-${each.key}-secret-read"
  role     = aws_iam_role.ecs_task[each.key].id
  policy   = data.aws_iam_policy_document.ecs_task_secret_access[each.key].json
}

resource "aws_secretsmanager_secret" "app_config" {
  for_each                = toset(local.environments)
  name                    = "${var.project_name}/${each.key}/app-config"
  description             = "Environment-specific config/secrets for ${each.key}, injected at runtime."
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

resource "aws_cloudwatch_log_group" "app" {
  for_each          = toset(local.environments)
  name              = "/ecs/${var.project_name}-${each.key}"
  retention_in_days = 14
}

resource "aws_ecs_task_definition" "app" {
  for_each                 = toset(local.environments)
  family                   = "${var.project_name}-${each.key}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution[each.key].arn
  task_role_arn            = aws_iam_role.ecs_task[each.key].arn

  container_definitions = jsonencode([
    {
      name      = "app"
      image     = "${aws_ecr_repository.app.repository_url}:bootstrap"
      essential = true
      portMappings = [
        { containerPort = 8080, protocol = "tcp" }
      ]
      environment = [
        { name = "APP_ENV", value = each.key },
        { name = "APP_SECRET_ARN", value = aws_secretsmanager_secret.app_config[each.key].arn },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app[each.key].name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "app"
        }
      }
    }
  ])

  lifecycle {
    ignore_changes = [container_definitions]
  }
}

resource "aws_ecs_service" "app" {
  for_each        = toset(local.environments)
  name            = "${var.project_name}-${each.key}"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.app[each.key].arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.app[each.key].id]
    assign_public_ip = true
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  depends_on = [aws_ecs_cluster_capacity_providers.this]

  lifecycle {
    ignore_changes = [task_definition]
  }
}
