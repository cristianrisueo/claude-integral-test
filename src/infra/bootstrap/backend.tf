terraform {
  backend "s3" {
    bucket       = "claude-integral-test-tfstate-685562352363"
    key          = "bootstrap/terraform.tfstate"
    region       = "eu-west-1"
    encrypt      = true
    use_lockfile = true
  }
}
