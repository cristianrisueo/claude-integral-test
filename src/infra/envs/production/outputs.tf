# What CD and verify read from the production state.

output "url" {
  description = "The site's HTTPS address."
  value       = "https://${aws_cloudfront_distribution.web.domain_name}"
}

output "web_bucket" {
  description = "The bucket CD publishes the web build to."
  value       = aws_s3_bucket.web.bucket
}

output "distribution_id" {
  description = "The distribution CD invalidates after a publish."
  value       = aws_cloudfront_distribution.web.id
}

output "ecr_repository_url" {
  description = "The repository CD pushes the API image to."
  value       = aws_ecr_repository.api.repository_url
}

output "ecs_cluster" {
  description = "The cluster of the API service."
  value       = aws_ecs_cluster.main.name
}

output "ecs_service" {
  description = "The API service CD rolls."
  value       = aws_ecs_service.api.name
}
