# Shared defaults for the mocked AWS provider, loaded by every test file with
# `source = "./tests/mocks"`. The mock returns an empty list for computed
# blocks and random strings for computed attributes, so:
# - the RDS-managed secret gets a value (the task definition reads
#   master_user_secret[0].secret_arn);
# - the ARNs other resources validate get the ARN shape, one per role so a
#   swapped role still fails its test;
# - the managed CloudFront policies get their real, distinct ids, so a
#   swapped policy still fails its test.

mock_resource "aws_db_instance" {
  defaults = {
    master_user_secret = [{
      secret_arn    = "arn:aws:secretsmanager:eu-west-1:685562352363:secret:rds!db-mock"
      kms_key_id    = "mock"
      secret_status = "active"
    }]
  }
}

mock_resource "aws_lb" {
  defaults = {
    arn = "arn:aws:elasticloadbalancing:eu-west-1:685562352363:loadbalancer/app/mock/0000000000000000"
  }
}

mock_resource "aws_lb_target_group" {
  defaults = {
    arn = "arn:aws:elasticloadbalancing:eu-west-1:685562352363:targetgroup/mock/0000000000000000"
  }
}

override_resource {
  target = aws_iam_role.execution
  values = {
    arn = "arn:aws:iam::685562352363:role/mock-execution"
  }
}

override_resource {
  target = aws_iam_role.task
  values = {
    arn = "arn:aws:iam::685562352363:role/mock-task"
  }
}
