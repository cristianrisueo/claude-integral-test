# Exact pins, the same as src/infra/bootstrap/versions.tf. Bump required_version
# together with terraform_version in .github/workflows/ci.yml (checks and
# terraform jobs), and re-run terraform providers lock when the provider
# changes so .terraform.lock.hcl follows.
terraform {
  required_version = "1.15.3"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.70.0"
    }
  }
}
