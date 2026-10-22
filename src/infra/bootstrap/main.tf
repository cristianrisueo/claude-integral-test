# One-time bootstrap: the remote-state bucket and the GitHub OIDC roles that
# CI/CD assume. Cristian applies it once by hand (see README.md); CI never
# plans or applies it. State starts local and is then migrated to the bucket.

locals {
  account_id   = "685562352363"
  region       = "eu-west-1"
  repo         = "cristianrisueo/claude-integral-test"
  state_bucket = "claude-integral-test-tfstate-${local.account_id}"
}

provider "aws" {
  region = local.region

  # Refuses to plan or apply against any other account.
  allowed_account_ids = [local.account_id]

  default_tags {
    tags = {
      Project   = "claude-integral-test"
      ManagedBy = "terraform/bootstrap"
    }
  }
}
