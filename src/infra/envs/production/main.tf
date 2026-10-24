# Production: everything here is short-lived and destroyed by destroy.yml.
# The bootstrap resources (state bucket, OIDC provider, plan and deploy roles)
# are not managed here.

locals {
  account_id = "685562352363"
  region     = "eu-west-1"
  name       = "claude-integral"

  # Fixed zones instead of a lookup: the plan and the mocked tests stay the
  # same everywhere.
  zones = {
    a = "eu-west-1a"
    b = "eu-west-1b"
  }
}

provider "aws" {
  region = local.region

  # Refuses to plan or apply against any other account.
  allowed_account_ids = [local.account_id]

  default_tags {
    tags = {
      Project   = "claude-integral-test"
      ManagedBy = "terraform/production"
    }
  }
}
