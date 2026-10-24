# Slice report: bootstrap 04 — Production compute and edge

## What was done

The production root in `src/infra/envs/production/` now describes the whole site. Nothing is created yet: this slice only describes it, and the pull request plans it.

It adds four things:

- **The API on ECS** (`compute.tf`).
  - One Fargate task: 0.25 vCPU, 512 MB, linux/amd64.
  - It runs the image tagged `live` from the registry, on port 8080.
  - It gets the database settings from RDS: `PGHOST`, `PGPORT`, `PGUSER`, `PGDATABASE`, and `PGSSLMODE=require`.
  - `PGPASSWORD` comes from the secret that RDS keeps. It is never written in the code.
  - Logs go to a log group this root owns, kept 7 days.
  - The task runs in the public subnets with a public IP and the API's security group.
- **The load balancer** (`edge.tf`). It listens on port 80 and sends traffic to the API on 8080. It checks `/api/health` and counts both 200 and 503 as healthy, so a database outage shows on the page instead of ECS restarting the API in a loop.
- **The page and the address** (`web.tf`).
  - A private bucket that blocks all public access. Only the CloudFront distribution can read it.
  - CloudFront sends `/api/*` to the load balancer with no caching, and every other path to the bucket. `index.html` is the default page, and HTTP redirects to HTTPS.
- **The outputs CD needs** (`outputs.tf`): `url`, `web_bucket`, `distribution_id`, `ecr_repository_url`, `ecs_cluster`, `ecs_service`.

Six new Terraform tests check this against a fake AWS, with no account and no cost. Two new runs went into the existing `destroy.tftest.hcl`. The other four are in the new files `routing.tftest.hcl` and `compute.tftest.hcl`.

**The two test files from slice 03 were touched, but not weakened.** The fake AWS returns an empty database secret and random ARNs, which the new code cannot use. A new shared file, `tests/mocks/aws.tfmock.hcl`, gives it realistic values, with a distinct ARN for each role so a swapped role still fails. Both existing files now load it with one line, `source = "./tests/mocks"`. No assertion was changed, and their four runs still pass.

Decisions made on Cristian's behalf:

- **The web bucket gets a generated name** (`claude-integral-web-…`). AWS can keep a deleted bucket name unavailable for a while, which would block a re-create right after a destroy. CD reads the name from `web_bucket`.
- **CloudFront's ready-made policies are referenced by their fixed ids, not looked up by name.** This differs from the approved plan. The fake AWS leaves a name lookup's id empty, so the tests could not tell "no caching" from "caching" apart. AWS documents these ids, and they never change.
- **CloudFront uses only its cheapest set of locations** (`PriceClass_100`).
- **`/api/*` accepts every HTTP method**, ready for the users CRUD. It forwards the visitor's headers, cookies and query strings, except `Host`.
- **No automatic rollback (ECS circuit breaker), and Terraform does not wait for the API to start.** On a deploy from nothing, the service exists before CD pushes the `live` image. CD (slice 06) waits for the service, and verify checks the version.
- **The load balancer drains an old task in 30 seconds**, instead of 5 minutes, so restarts and destroys are faster.
- **Permissions are kept minimal.** The task role has none, because the API calls no AWS service. The execution role has AWS's standard ECS policy, plus permission to read the database secret only.
- **The load balancer and the service wait for the internet route.** On a deploy from nothing, the load balancer cannot be created before the internet gateway. On a destroy, the gateway cannot be removed while they still use it.
- **The container settings are written the way AWS returns them** (sorted variables, an explicit host port, text values). A later plan should then show no change when nothing changed. Only a second plan after the first real deploy (slice 07) can confirm this.

Things later slices should know:

- **Changing the task definition, or the target group's port, protocol or type, replaces the resource, and plan-guard rejects any replacement.** Such a change needs a destroy and a fresh deploy.
- **RDS changes the database password every 7 days, and a running task keeps the old one.** A production that stays up longer than that needs a redeploy.

## How we checked it

| Criterion | Test or command | Result |
| --------- | --------------- | ------ |
| AC1: `/api/*` goes to the load balancer uncached, the rest to the bucket, HTTP redirects to HTTPS | `routes_api_to_alb` in `tests/routing.tftest.hcl`, via `make check-infra` | pass |
| AC2: the target group checks `/api/health` and counts 200 and 503 as healthy | `health_check_accepts_503` in `tests/routing.tftest.hcl`, via `make check-infra` | pass |
| AC3: the task runs `live` on 8080, with `PGHOST` from RDS, `PGSSLMODE=require` and `PGPASSWORD` from the RDS secret | `task_uses_live_image_and_database` in `tests/compute.tftest.hcl`, via `make check-infra` | pass |
| AC4: the web bucket is deleted with its files, blocks public access, and only the distribution reads it | `bucket_is_private_and_destroyable` in `tests/destroy.tftest.hcl`, via `make check-infra` | pass |
| AC5: the load balancer has no deletion protection, and this root manages the log group | `edge_is_destroyable` in `tests/destroy.tftest.hcl`, via `make check-infra` | pass |
| AC6: the outputs CD needs exist | `outputs_for_cd` in `tests/compute.tftest.hcl`, via `make check-infra` | pass |
| AC7: format, validate and every Terraform test pass | `make check-infra` | pass: both folders valid, 10 passed, 0 failed |
| AC8: the plan of this PR deletes and replaces nothing | the `terraform` check of PR #18 ([run 40106178305](https://github.com/cristianrisueo/claude-integral-test/actions/runs/40106178305/job/120908217926)): `gh pr checks 18` | pass: `Plan: 35 to add, 0 to change, 0 to destroy.`; `plan-guard: ok, no resource is deleted or replaced` |

## Check it yourself

1. `make check-infra` — you should see `Success! 10 passed, 0 failed.`
2. `gh pr checks 18` — the `terraform` check is green, and its log ends with `plan-guard: ok, no resource is deleted or replaced`.
3. `gh run download 40106178305 -n terraform-plan && grep '^Plan:' plan.txt` — you should see `Plan: 35 to add, 0 to change, 0 to destroy.` (slice 03 had 19).
