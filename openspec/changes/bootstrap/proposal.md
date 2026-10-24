# Proposal: bootstrap

## What we'll build

A hello world that crosses the whole stack. A Go API answers a health check that reaches Postgres, and a React page shows that answer.
The same app runs on your machine under docker compose. It also runs in a short-lived AWS production that GitHub workflows create, verify and destroy, each run after your approval.

## What you'll see when it's done

- `make up`, then http://localhost:3000: a page that says "API: ok" and "Database: ok".
- `GET /api/health` answers `{"status":"ok","database":"ok"}`. With the database stopped, it answers 503 and the page says "Database: unreachable".
- Three new GitHub workflows:
  - `cd.yml` deploys;
  - `verify.yml` checks the live site;
  - `destroy.yml` removes production.

  Deploys and destroys show you the plan first, then wait for your approval.
- While production is up, in AWS `eu-west-1`:
  - a network of its own;
  - a Postgres database (RDS) and an image registry (ECR);
  - the API on ECS behind a load balancer;
  - the page in S3 behind CloudFront.

  The site lives at `https://<id>.cloudfront.net`.
- After a destroy, nothing of production is left in AWS. The bootstrap state bucket and roles are untouched.

## How we'll know it works

- `make test`: the API tests (database reachable and unreachable) and the page tests (each state) pass.
- `make e2e` passes on your machine, and the CI `e2e` job runs it on every pull request.
- `make check-infra`: Terraform tests show, without touching AWS, that production can be destroyed and that `/api/*` reaches the API.
- Every pull request plans production in CI, and plan-guard confirms the plan deletes and replaces nothing.
- The last slice runs a round trip in GitHub: destroy, deploy from nothing, verify by hand, destroy again.
  - Each run is green on its first attempt.
  - The slice report links every run.
  - The change ends with production destroyed.

## Decisions

- **One health endpoint.** The load balancer counts both 200 and 503 as "alive". A database outage then shows on the page. Without this, AWS would restart the API in a loop.
- **No NAT gateway.** The API runs in public subnets, but accepts traffic only from the load balancer. The database has no route to the internet. This is the cheapest layout: about $1.7 a day while production is up.
- **When `cd.yml` runs.**
  - It runs when a push to main changes `src/api`, `src/web`, `src/infra/envs` or `cd.yml` itself.
  - You can also start it by hand, to re-create production after a destroy.
  - After a destroy, a merge that triggers it waits for your approval. Reject it to keep production down.
- **You approve after seeing the plan.**
  - A first job plans with the read-only role and prints the plan. The approved job applies exactly that plan.
  - The deploy also runs plan-guard, so a deploy never deletes or replaces anything. Only `destroy.yml` deletes.
- **Verification.**
  - `verify.yml` is the last job of every deploy, and you can run it by hand at any time.
  - It needs no approval, because it only reads.
  - It checks `/api/health`, then runs the end-to-end tests against the live site.
  - A failure turns the run red. Nothing is rolled back automatically.
- **Everything is destroyable in one run.**
  - The database has no deletion protection, no final snapshot and no backups.
  - The registry and the web bucket are deleted with their contents.
  - AWS generates the database password, so a re-create never collides with a secret still pending deletion.
  - The state bucket is not part of production and stays protected.
- **The API always runs the image tagged `live`.** Each deploy pushes a new `live` image and restarts the service. The Terraform plan then stays the same between commits, so plan-guard does not flag every deploy.
- **No custom domain.**
  - The site uses CloudFront's own address.
  - CloudFront talks to the load balancer over plain HTTP inside AWS, because a load balancer without a domain cannot have a certificate.
  - The load balancer accepts only CloudFront.
- **The local stack mirrors production.**
  - The page and `/api` share one address, as they do behind CloudFront.
  - The API runs the same image that ships.
- **PostgreSQL 17, locally and on RDS.** On RDS: the smallest instance, one zone, TLS required. The local password `app` lives in `docker-compose.yml` and only works on your machine.
- **No overlap.** `cd.yml` and `destroy.yml` never run at the same time.
- **Harness prerequisite.** Before slice 01, a chore PR outside this change updates the harness:
  - CLAUDE.md lets a change edit `cd.yml`, `destroy.yml`, `verify.yml` and the `checks`, `e2e` and `terraform` jobs of `ci.yml`.
  - A change never edits the harness jobs of `ci.yml` (`harness`, `spec`, `audit`), the pull request template, or anything else under `.github/`.
  - The audit checks this from the diff. You still approve every workflow edit.
  - `make check-infra` also runs the Terraform tests.
- **Proving the workflows.**
  - A workflow you start by hand can only run once it is on main, so slices 05 and 06 are checked statically before merge.
  - Slice 07 proves both workflows with real runs.
  - Slice 07 changes no workflow or infrastructure code. If a run fails, it stops and reports, and you decide the fix.

## Out of scope

- The users CRUD: tables, migrations and endpoints. golang-migrate arrives with the first table.
- A custom domain, and HTTPS between CloudFront and the load balancer.
- High availability, backups, autoscaling, alarms and a firewall: production is short-lived.
- An automatic rollback after a failed verification.
- A least-privilege deploy role, and a separate database user for the API. Each is a later change.
- Any change to `src/infra/bootstrap/`.
