# The bootstrap state bucket, under this root's own key. The bucket itself is
# managed by src/infra/bootstrap/, never here.
terraform {
  backend "s3" {
    bucket       = "claude-integral-test-tfstate-685562352363"
    key          = "production/terraform.tfstate"
    region       = "eu-west-1"
    encrypt      = true
    use_lockfile = true
  }
}
