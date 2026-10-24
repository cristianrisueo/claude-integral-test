# The API on ECS Fargate: one task running the `live` image, in the public
# subnets with a public IP (no NAT gateway), reachable only through the load
# balancer. CD pushes `live` and rolls the service, so this file stays the
# same between commits and the plan shows no change.
#
# The container definition is written the way ECS returns it (essential,
# hostPort, sorted environment, string values): any difference would replace
# the task definition, and plan-guard rejects replacements.

resource "aws_cloudwatch_log_group" "api" {
  name              = "/ecs/${local.name}-api"
  retention_in_days = 7
}

# --- Roles ------------------------------------------------------------------

locals {
  ecs_tasks_trust = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })

  database_secret_arn = aws_db_instance.main.master_user_secret[0].secret_arn
}

# Used by ECS to pull the image, write logs and read the database password.
resource "aws_iam_role" "execution" {
  name               = "${local.name}-api-execution"
  assume_role_policy = local.ecs_tasks_trust
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# The RDS-managed secret uses the AWS-managed key, so no KMS permission.
resource "aws_iam_role_policy" "execution_secrets" {
  name = "database-secret"
  role = aws_iam_role.execution.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "secretsmanager:GetSecretValue"
      Resource = local.database_secret_arn
    }]
  })
}

# Assumed by the API itself, which calls no AWS service.
resource "aws_iam_role" "task" {
  name               = "${local.name}-api-task"
  assume_role_policy = local.ecs_tasks_trust
}

# --- Cluster, task and service ----------------------------------------------

resource "aws_ecs_cluster" "main" {
  name = local.name
}

resource "aws_ecs_task_definition" "api" {
  family                   = "${local.name}-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name      = "api"
    image     = "${aws_ecr_repository.api.repository_url}:live"
    essential = true

    portMappings = [{ containerPort = 8080, hostPort = 8080, protocol = "tcp" }]

    environment = [
      { name = "PGDATABASE", value = aws_db_instance.main.db_name },
      { name = "PGHOST", value = aws_db_instance.main.address },
      { name = "PGPORT", value = tostring(aws_db_instance.main.port) },
      { name = "PGSSLMODE", value = "require" },
      { name = "PGUSER", value = aws_db_instance.main.username },
    ]

    # The secret RDS keeps holds {"username", "password"}.
    secrets = [{ name = "PGPASSWORD", valueFrom = "${local.database_secret_arn}:password::" }]

    # The log group above, never one ECS creates (a destroy would leave it).
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.api.name
        "awslogs-region"        = local.region
        "awslogs-stream-prefix" = "api"
      }
    }
  }])
}

# No circuit breaker and no wait for a steady state: on a deploy from nothing
# the service exists before CD pushes `live`, and CD waits for it instead.
resource "aws_ecs_service" "api" {
  name            = "${local.name}-api"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.api.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    subnets          = [for s in aws_subnet.public : s.id]
    security_groups  = [aws_security_group.api.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.api.arn
    container_name   = "api"
    container_port   = 8080
  }

  # Created after, and destroyed before, what its tasks need: the listener
  # that attaches the target group, the execution permissions and the route
  # to the internet (image pulls and logs).
  depends_on = [
    aws_lb_listener.http,
    aws_iam_role_policy_attachment.execution,
    aws_iam_role_policy.execution_secrets,
    aws_route.internet,
  ]
}
