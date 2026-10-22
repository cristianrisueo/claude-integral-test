output "state_bucket" {
  description = "S3 bucket for every Terraform state (TF_STATE_BUCKET)"
  value       = aws_s3_bucket.state.bucket
}

output "plan_role_arn" {
  description = "Role for terraform plan in CI (AWS_PLAN_ROLE_ARN)"
  value       = aws_iam_role.plan.arn
}

output "deploy_role_arn" {
  description = "Role for terraform apply in the production environment (AWS_DEPLOY_ROLE_ARN)"
  value       = aws_iam_role.deploy.arn
}
