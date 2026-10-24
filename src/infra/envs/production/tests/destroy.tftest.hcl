# Destroy-ready resources: one terraform destroy removes everything, with data
# inside, and nothing AWS keeps reserved blocks a re-create. Mocked provider:
# no AWS call, no credentials.

mock_provider "aws" {
  source = "./tests/mocks"
}

run "database_is_destroyable" {
  command = apply

  assert {
    condition     = aws_db_instance.main.deletion_protection == false
    error_message = "The database must have no deletion protection."
  }

  assert {
    condition     = aws_db_instance.main.skip_final_snapshot == true
    error_message = "The database must skip the final snapshot."
  }

  assert {
    condition     = aws_db_instance.main.backup_retention_period == 0
    error_message = "The database must keep no automated backups (retention 0)."
  }

  assert {
    condition     = aws_db_instance.main.delete_automated_backups == true
    error_message = "The database must delete its automated backups with it."
  }

  assert {
    condition     = aws_db_instance.main.manage_master_user_password == true && aws_db_instance.main.password == null
    error_message = "RDS must manage the database password; Terraform must not set one."
  }
}

run "registry_is_destroyable" {
  command = apply

  assert {
    condition     = aws_ecr_repository.api.force_delete == true
    error_message = "The ECR repository must be deleted together with its images."
  }

  assert {
    condition     = one(aws_ecr_repository.api.encryption_configuration).encryption_type == "AES256"
    error_message = "The ECR repository must use AES256, not a customer-managed KMS key."
  }
}

run "bucket_is_private_and_destroyable" {
  command = apply

  assert {
    condition     = aws_s3_bucket.web.force_destroy == true
    error_message = "The web bucket must be deleted together with its files."
  }

  assert {
    condition = (
      aws_s3_bucket_public_access_block.web.bucket == aws_s3_bucket.web.id
      && aws_s3_bucket_public_access_block.web.block_public_acls == true
      && aws_s3_bucket_public_access_block.web.block_public_policy == true
      && aws_s3_bucket_public_access_block.web.ignore_public_acls == true
      && aws_s3_bucket_public_access_block.web.restrict_public_buckets == true
    )
    error_message = "The web bucket must block all public access."
  }

  assert {
    condition = (
      aws_s3_bucket_policy.web.bucket == aws_s3_bucket.web.id
      && jsondecode(aws_s3_bucket_policy.web.policy).Statement == [{
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.web.arn}/*"
        Condition = { StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.web.arn } }
      }]
    )
    error_message = "Only the distribution may read the web bucket."
  }

  assert {
    condition     = one([for o in aws_cloudfront_distribution.web.origin : o.origin_access_control_id if o.origin_id == "web"]) == aws_cloudfront_origin_access_control.web.id
    error_message = "The web origin must sign its requests with the origin access control."
  }

  assert {
    condition = (
      aws_cloudfront_origin_access_control.web.origin_access_control_origin_type == "s3"
      && aws_cloudfront_origin_access_control.web.signing_behavior == "always"
      && aws_cloudfront_origin_access_control.web.signing_protocol == "sigv4"
    )
    error_message = "The origin access control must sign every S3 request with SigV4."
  }
}

run "edge_is_destroyable" {
  command = apply

  assert {
    condition     = aws_lb.api.enable_deletion_protection == false
    error_message = "The load balancer must have no deletion protection."
  }

  assert {
    condition     = aws_cloudwatch_log_group.api.retention_in_days == 7
    error_message = "The API logs must be kept 7 days."
  }

  assert {
    condition = (
      jsondecode(aws_ecs_task_definition.api.container_definitions)[0].logConfiguration.logDriver == "awslogs"
      && jsondecode(aws_ecs_task_definition.api.container_definitions)[0].logConfiguration.options["awslogs-group"] == aws_cloudwatch_log_group.api.name
    )
    error_message = "The API must log to the log group this root manages."
  }

  assert {
    condition     = !contains(keys(jsondecode(aws_ecs_task_definition.api.container_definitions)[0].logConfiguration.options), "awslogs-create-group")
    error_message = "ECS must not create a log group of its own, which a destroy would leave behind."
  }

  assert {
    condition = (
      aws_cloudwatch_log_group.api.skip_destroy != true
      && aws_ecs_task_definition.api.skip_destroy != true
      && aws_cloudfront_distribution.web.retain_on_delete != true
    )
    error_message = "A destroy must delete the log group, the task definition and the distribution."
  }
}
