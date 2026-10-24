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
