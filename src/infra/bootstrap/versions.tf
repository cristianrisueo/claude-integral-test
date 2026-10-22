# Exact pins. Bump required_version together with terraform_version in
# .github/workflows/ci.yml (checks job), and re-run terraform init -upgrade
# when the provider changes so .terraform.lock.hcl follows.
terraform {
  required_version = "1.15.3"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.70.0"
    }
  }
}
