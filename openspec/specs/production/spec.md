# Production specification

## Purpose

How the system runs in AWS (`eu-west-1`): the API on ECS Fargate behind a load balancer, the database on RDS, and the page on S3 behind CloudFront, which also routes `/api/*` to the API.

## Requirements

### Requirement: Load balancer health check

The load balancer's target group SHALL check each API task with `GET /api/live` on the traffic port, and MUST count only 200 as healthy.
It MUST NOT check `/api/health`, so that a database outage never marks a task unhealthy.

#### Scenario: Running task

- **WHEN** an API task is running and answers `/api/live` with 200
- **THEN** the target group marks it healthy and the load balancer sends it traffic

#### Scenario: Database down

- **WHEN** the database is unreachable while an API task is running
- **THEN** the task stays healthy and is not replaced
- **AND** `https://<id>.cloudfront.net/api/health` responds 503, so the page shows "Database: unreachable"
