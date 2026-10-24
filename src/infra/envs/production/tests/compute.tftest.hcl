# The API task: the `live` image on port 8080, its database settings from
# RDS, and the outputs CD reads. Mocked provider: no AWS call, no credentials.

mock_provider "aws" {
  source = "./tests/mocks"
}

run "task_uses_live_image_and_database" {
  command = apply

  assert {
    condition     = length(jsondecode(aws_ecs_task_definition.api.container_definitions)) == 1
    error_message = "The task must run exactly one container."
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.api.container_definitions)[0].image == "${aws_ecr_repository.api.repository_url}:live"
    error_message = "The task must run the live image of the API repository."
  }

  assert {
    condition = (
      length(jsondecode(aws_ecs_task_definition.api.container_definitions)[0].portMappings) == 1
      && jsondecode(aws_ecs_task_definition.api.container_definitions)[0].portMappings[0].containerPort == 8080
    )
    error_message = "The container must expose port 8080 only."
  }

  assert {
    condition = (
      { for e in jsondecode(aws_ecs_task_definition.api.container_definitions)[0].environment : e.name => e.value } == {
        PGDATABASE = aws_db_instance.main.db_name
        PGHOST     = aws_db_instance.main.address
        PGPORT     = tostring(aws_db_instance.main.port)
        PGSSLMODE  = "require"
        PGUSER     = aws_db_instance.main.username
      }
    )
    error_message = "The environment must hold exactly PGDATABASE, PGHOST, PGPORT and PGUSER from RDS, and PGSSLMODE=require (no PGPASSWORD)."
  }

  assert {
    condition = (
      length(jsondecode(aws_ecs_task_definition.api.container_definitions)[0].secrets) == 1
      && jsondecode(aws_ecs_task_definition.api.container_definitions)[0].secrets[0].name == "PGPASSWORD"
      && jsondecode(aws_ecs_task_definition.api.container_definitions)[0].secrets[0].valueFrom == "${one(aws_db_instance.main.master_user_secret).secret_arn}:password::"
    )
    error_message = "PGPASSWORD must come from the password key of the RDS-managed secret."
  }

  assert {
    condition = (
      aws_ecs_task_definition.api.execution_role_arn == aws_iam_role.execution.arn
      && aws_ecs_task_definition.api.task_role_arn == aws_iam_role.task.arn
    )
    error_message = "The task must use the execution role and the task role."
  }

  assert {
    condition = (
      aws_iam_role_policy.execution_secrets.role == aws_iam_role.execution.id
      && jsondecode(aws_iam_role_policy.execution_secrets.policy).Statement == [{
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = one(aws_db_instance.main.master_user_secret).secret_arn
      }]
    )
    error_message = "The execution role must be able to read the RDS-managed secret, and only it."
  }

  assert {
    condition = (
      aws_ecs_task_definition.api.cpu == "256" && aws_ecs_task_definition.api.memory == "512"
      && aws_ecs_task_definition.api.requires_compatibilities == toset(["FARGATE"])
      && aws_ecs_task_definition.api.network_mode == "awsvpc"
      && one(aws_ecs_task_definition.api.runtime_platform).cpu_architecture == "X86_64"
      && one(aws_ecs_task_definition.api.runtime_platform).operating_system_family == "LINUX"
    )
    error_message = "The task must be Fargate, 0.25 vCPU / 512 MB, linux/amd64."
  }

  assert {
    condition = (
      aws_ecs_service.api.cluster == aws_ecs_cluster.main.id
      && aws_ecs_service.api.task_definition == aws_ecs_task_definition.api.arn
      && aws_ecs_service.api.launch_type == "FARGATE"
    )
    error_message = "The service must run the API task on Fargate in the cluster."
  }

  assert {
    condition = (
      one(aws_ecs_service.api.load_balancer).target_group_arn == aws_lb_target_group.api.arn
      && one(aws_ecs_service.api.load_balancer).container_name == "api"
      && one(aws_ecs_service.api.load_balancer).container_port == 8080
    )
    error_message = "The service must register the api container on 8080 in the target group."
  }

  assert {
    condition = (
      one(aws_ecs_service.api.network_configuration).security_groups == toset([aws_security_group.api.id])
      && one(aws_ecs_service.api.network_configuration).subnets == toset([for s in aws_subnet.public : s.id])
      && one(aws_ecs_service.api.network_configuration).assign_public_ip == true
    )
    error_message = "The tasks must run in the public subnets, with a public IP and only the API security group."
  }
}

run "outputs_for_cd" {
  command = apply

  assert {
    condition     = output.url == "https://${aws_cloudfront_distribution.web.domain_name}"
    error_message = "url must be the distribution's HTTPS address."
  }

  assert {
    condition     = output.web_bucket == aws_s3_bucket.web.bucket
    error_message = "web_bucket must be the web bucket's name."
  }

  assert {
    condition     = output.distribution_id == aws_cloudfront_distribution.web.id
    error_message = "distribution_id must be the distribution's id."
  }

  assert {
    condition     = output.ecr_repository_url == aws_ecr_repository.api.repository_url
    error_message = "ecr_repository_url must be the API repository's URL."
  }

  assert {
    condition     = output.ecs_cluster == aws_ecs_cluster.main.name
    error_message = "ecs_cluster must be the cluster's name."
  }

  assert {
    condition     = output.ecs_service == aws_ecs_service.api.name
    error_message = "ecs_service must be the service's name."
  }
}
