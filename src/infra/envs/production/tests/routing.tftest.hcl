# Single HTTPS origin: CloudFront serves the page from the bucket and sends
# /api/* to the load balancer, uncached; the load balancer counts 503 as alive.
# Mocked provider: no AWS call, no credentials.

mock_provider "aws" {
  source = "./tests/mocks"
}

run "routes_api_to_alb" {
  command = apply

  assert {
    condition     = one(aws_cloudfront_distribution.web.default_cache_behavior).target_origin_id == "web"
    error_message = "Every path other than /api/* must go to the web origin."
  }

  assert {
    condition     = one([for o in aws_cloudfront_distribution.web.origin : o.domain_name if o.origin_id == "web"]) == aws_s3_bucket.web.bucket_regional_domain_name
    error_message = "The web origin must be the web bucket."
  }

  assert {
    condition     = one(aws_cloudfront_distribution.web.default_cache_behavior).cache_policy_id == "658327ea-f89d-4fab-a63d-7e88639e58f6"
    error_message = "The page must use the managed CachingOptimized policy (658327ea-…)."
  }

  assert {
    condition     = length(aws_cloudfront_distribution.web.ordered_cache_behavior) == 1
    error_message = "There must be exactly one ordered behavior, for /api/*."
  }

  assert {
    condition = (
      try(aws_cloudfront_distribution.web.ordered_cache_behavior[0].path_pattern, null) == "/api/*"
      && try(aws_cloudfront_distribution.web.ordered_cache_behavior[0].target_origin_id, null) == "api"
    )
    error_message = "/api/* must go to the api origin."
  }

  assert {
    condition     = one([for o in aws_cloudfront_distribution.web.origin : o.domain_name if o.origin_id == "api"]) == aws_lb.api.dns_name
    error_message = "The api origin must be the load balancer."
  }

  assert {
    condition     = try(one(one([for o in aws_cloudfront_distribution.web.origin : o if o.origin_id == "api"]).custom_origin_config).origin_protocol_policy, null) == "http-only"
    error_message = "CloudFront must reach the load balancer over plain HTTP (it has no certificate)."
  }

  assert {
    condition     = try(aws_cloudfront_distribution.web.ordered_cache_behavior[0].cache_policy_id, null) == "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    error_message = "/api/* must use the managed CachingDisabled policy (4135ea2d-…)."
  }

  assert {
    condition = alltrue([
      for b in concat(aws_cloudfront_distribution.web.default_cache_behavior, aws_cloudfront_distribution.web.ordered_cache_behavior) :
      b.viewer_protocol_policy == "redirect-to-https"
    ])
    error_message = "Every behavior must redirect HTTP to HTTPS."
  }

  assert {
    condition     = aws_cloudfront_distribution.web.default_root_object == "index.html"
    error_message = "The default root object must be index.html."
  }

  assert {
    condition     = aws_lb.api.internal == false && aws_lb.api.security_groups == toset([aws_security_group.load_balancer.id])
    error_message = "The load balancer must be internet-facing and use only the load balancer security group."
  }
}

run "health_check_accepts_503" {
  command = apply

  assert {
    condition     = one(aws_lb_target_group.api.health_check).path == "/api/health"
    error_message = "The target group must check /api/health."
  }

  assert {
    condition     = one(aws_lb_target_group.api.health_check).matcher == "200,503"
    error_message = "The target group must count 200 and 503 as healthy."
  }

  assert {
    condition = (
      aws_lb_target_group.api.port == 8080 && aws_lb_target_group.api.protocol == "HTTP"
      && aws_lb_target_group.api.target_type == "ip" && aws_lb_target_group.api.vpc_id == aws_vpc.main.id
    )
    error_message = "The target group must send HTTP to the tasks' IPs on port 8080."
  }

  assert {
    condition = (
      aws_lb_listener.http.load_balancer_arn == aws_lb.api.arn
      && aws_lb_listener.http.port == 80 && aws_lb_listener.http.protocol == "HTTP"
    )
    error_message = "The load balancer must listen for HTTP on port 80."
  }

  assert {
    condition = (
      one(aws_lb_listener.http.default_action).type == "forward"
      && one(aws_lb_listener.http.default_action).target_group_arn == aws_lb_target_group.api.arn
    )
    error_message = "The listener must forward to the API target group."
  }
}
