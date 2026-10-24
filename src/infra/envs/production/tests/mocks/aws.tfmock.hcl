# Shared defaults for the mocked AWS provider, loaded by every test file with
# `source = "./tests/mocks"`. The mock returns an empty list for computed
# blocks, so the RDS-managed secret gets a value here: the task definition
# reads master_user_secret[0].secret_arn.

mock_resource "aws_db_instance" {
  defaults = {
    master_user_secret = [{
      secret_arn    = "arn:aws:secretsmanager:eu-west-1:685562352363:secret:rds!db-mock"
      kms_key_id    = "mock"
      secret_status = "active"
    }]
  }
}
