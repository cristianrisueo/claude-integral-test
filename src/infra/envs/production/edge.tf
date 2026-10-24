# The load balancer in front of the API. Its security group admits only
# CloudFront, which reaches it over plain HTTP: without a domain it cannot
# have a certificate.

resource "aws_lb" "api" {
  name               = local.name
  internal           = false
  load_balancer_type = "application"
  subnets            = [for s in aws_subnet.public : s.id]
  security_groups    = [aws_security_group.load_balancer.id]

  enable_deletion_protection = false

  # An internet-facing load balancer needs the internet gateway, and a
  # destroy must remove it before detaching the gateway.
  depends_on = [aws_route.internet]
}

# The check uses /api/live, which only says the process is up and never asks
# the database, so a database outage never makes ECS replace the tasks; the
# page still shows it through /api/health. AWS accepts only 200-499 here, so
# /api/health's 503 could not count as healthy.
resource "aws_lb_target_group" "api" {
  name        = "${local.name}-api"
  port        = 8080
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.main.id

  deregistration_delay = 30

  health_check {
    path    = "/api/live"
    matcher = "200"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.api.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}
