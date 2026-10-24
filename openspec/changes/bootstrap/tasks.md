# Tasks: bootstrap

## Slice 01 — Health endpoint on local Postgres

**Goal:** `GET /api/health` reports the database on the local stack, served by the image that will ship.

**Requirements:** Health check, Start without the database, Database settings from the environment

**Scope:**

- The Go module in `src/api/`: `cmd/api` and the health handler in `internal/health`, with `pgx` and `slog`, and their tests.
- `src/api/Dockerfile`, for linux/amd64, listening on 8080.
- `docker-compose.yml` at the repository root, with two services:
  - `db`: PostgreSQL 17, user, password and database `app`, a named volume and a health check;
  - `api`: built from `src/api/`, with the `PG*` variables pointing at `db` and `PGSSLMODE=disable`.

**Out of scope:**

- The web page and the `web` service (slice 02).
- Migrations and tables (a later change).
- Anything in AWS.

### Acceptance criteria

| ID  | Criterion | Verified by |
| --- | --------- | ----------- |
| AC1 | With a database that answers, `GET /api/health` responds 200 `{"status":"ok","database":"ok"}` with `Content-Type: application/json` and `Cache-Control: no-store` | `TestHealthDatabaseReachable` in `src/api/internal/health/health_test.go` |
| AC2 | With PostgreSQL unreachable (a real pool pointed at a closed port), it responds 503 `{"status":"unavailable","database":"unreachable"}` in under 3 seconds, with no error detail in the body | `TestHealthDatabaseUnreachable` in `src/api/internal/health/health_test.go` |
| AC3 | Once the database answers again, the next call responds 200 without a restart | `TestHealthRecovers` in `src/api/internal/health/health_test.go` |
| AC4 | The server starts and listens on 8080 while PostgreSQL is unreachable | `TestServerStartsWithoutDatabase` in `src/api/cmd/api/main_test.go` |
| AC5 | Connection settings come only from the `PG*` variables | `TestConfigFromEnvironment` in `src/api/cmd/api/main_test.go` |
| AC6 | On the local stack, the endpoint reports the real database | `make up`, then `curl -si http://localhost:8080/api/health` prints `200` and `{"status":"ok","database":"ok"}` |
| AC7 | With `db` stopped, the endpoint reports it unreachable | `docker compose stop db`, then `curl -si http://localhost:8080/api/health` prints `503`; then `make up` |
| AC8 | Format, vet and tests are green | `make check` and `make test` |

## Slice 02 — Status page and end-to-end suite

**Goal:** the page shows the health status on the local stack, and every pull request runs the end-to-end suite.

**Requirements:** Show the health status, Local stack, End-to-end suite, End-to-end tests on pull requests

**Scope:**

- `src/web/`:
  - React + Vite + TypeScript;
  - the scripts `lint`, `typecheck` and `test` (Vitest with Testing Library);
  - a Vite dev proxy for `/api`.
- `src/web/Dockerfile`: the Vite build, served by nginx with `/api/` proxied to `api`.
- The `web` service in `docker-compose.yml`, on localhost:3000.
- `src/e2e/`: Playwright with chromium, `BASE_URL` defaulting to http://localhost:3000, and tests for the page and for `/api/health`.
- The `e2e` job of `ci.yml`: `npm ci`, the Playwright browsers, `make up`, `make e2e`, the compose logs on failure, then `make down`.

**Out of scope:**

- Anything in AWS.
- Every other job of `ci.yml`.

### Acceptance criteria

| ID   | Criterion | Verified by |
| ---- | --------- | ----------- |
| AC1  | While the health response is pending, the page shows "Checking…" | "shows checking while the request is pending" in `src/web/src/App.test.tsx` |
| AC2  | The page calls `/api/health` on its own origin, and on 200 shows "API: ok" and "Database: ok" | "shows API and database ok" in `src/web/src/App.test.tsx` |
| AC3  | On 503, the page shows "API: ok" and "Database: unreachable" | "shows database unreachable on 503" in `src/web/src/App.test.tsx` |
| AC4  | On a failed request, the page shows "API: unreachable" and "Database: unknown" | "shows API unreachable when the request fails" in `src/web/src/App.test.tsx` |
| AC5  | On any other response (for example a 502 HTML page), the page shows "API: unreachable" and "Database: unknown" | "shows API unreachable on an unexpected response" in `src/web/src/App.test.tsx` |
| AC6  | The `web` service serves the page and proxies the API | `make up`, then `curl -s http://localhost:3000/api/health` prints `{"status":"ok","database":"ok"}`, and `curl -s http://localhost:3000/` prints the page's HTML |
| AC7  | With `db` stopped, the API answers 503 through `web` | `docker compose stop db`, then `curl -si http://localhost:3000/api/health` prints `503`; then `make up` |
| AC8  | The suite passes against the local stack | `make e2e`: "page shows API and database ok" and "GET /api/health answers 200 with database ok" in `src/e2e/tests/health.spec.ts` pass |
| AC9  | The suite targets `BASE_URL` | `BASE_URL=http://localhost:9 make e2e` fails every test with a connection refused on port 9 |
| AC10 | `make down` keeps the database volume | `make down`, then `docker volume ls` still lists the `db` volume; then `make up` |
| AC11 | The CI `e2e` job runs the suite | the `e2e` check of this PR is green and its log shows 2 tests passed: `gh pr checks <pr>` |
| AC12 | Lint, typecheck and unit tests are green | `make check` and `make test` |

## Slice 03 — Production network, database and registry

**Goal:** a production Terraform root holds the network, the database and the image registry, and every pull request shows its plan.

**Requirements:** Network isolation, Destroy-ready resources, Bootstrap stays protected, Plan on pull requests

**Scope:**

- `src/infra/envs/production/`:
  - the backend in the bootstrap state bucket, with the key `production/terraform.tfstate`;
  - the bootstrap's pins (terraform `1.15.3`, aws `6.70.0`);
  - the provider with `allowed_account_ids`;
  - a VPC in two zones, with public subnets and database subnets that have no route to the internet;
  - security groups for the load balancer, the API and the database;
  - RDS PostgreSQL 17 on db.t4g.micro;
  - the ECR repository for the API.
- Its tests under `tests/`, with a mock AWS provider.
- The `terraform` job of `ci.yml`, as its `TODO(bootstrap)` describes:
  - the OIDC plan role;
  - `fmt -check`, `init`, `validate` and `plan -lock-timeout=5m`;
  - plan-guard;
  - the `terraform-plan` artifact.

**Out of scope:**

- ECS, the load balancer itself, S3 and CloudFront (slice 04).
- Any apply.

### Acceptance criteria

| ID  | Criterion | Verified by |
| --- | --------- | ----------- |
| AC1 | The database has no deletion protection, skips the final snapshot, keeps no automated backups and lets RDS manage its password | run `database_is_destroyable` in `src/infra/envs/production/tests/destroy.tftest.hcl`, via `make check-infra` |
| AC2 | The ECR repository is deleted together with its images | run `registry_is_destroyable` in `src/infra/envs/production/tests/destroy.tftest.hcl`, via `make check-infra` |
| AC3 | The database is not publicly accessible, accepts only the API's security group on 5432, and sits in subnets with no route to the internet gateway | run `database_is_isolated` in `src/infra/envs/production/tests/network.tftest.hcl`, via `make check-infra` |
| AC4 | The API's security group admits only the load balancer's on 8080, and the load balancer's admits only CloudFront's origin-facing prefix list | run `edge_is_isolated` in `src/infra/envs/production/tests/network.tftest.hcl`, via `make check-infra` |
| AC5 | Format, validate and the Terraform tests pass | `make check-infra` |
| AC6 | Every pull request plans production with the read-only role, plan-guard prints ok, and the plan is published | the `terraform` check of this PR is green, its log shows `plan-guard: ok`, and `gh run download <run-id> -n terraform-plan` returns the plan text |
| AC7 | The plan manages none of the bootstrap resources | in that artifact, `grep -cE 'openid_connect_provider\|claude-integral-(plan\|deploy)\|tfstate-685562352363' plan.txt` prints `0` |
| AC8 | A plan that deletes or replaces a resource fails the job | `make harness-test` (`tools/plan-guard_test.sh`), and the job's plan-guard step has no `continue-on-error` |

## Slice 04 — Production compute and edge

**Goal:** the production root describes the whole site: the API on ECS behind the load balancer, the page in S3, both behind one CloudFront address.

**Requirements:** Single HTTPS origin, Network isolation, Destroy-ready resources

**Scope:**

- The ECS cluster.
- The task definition:
  - image `<ecr>:live`, 0.25 vCPU / 512 MB, linux/amd64;
  - the `PG*` variables from RDS, with `PGSSLMODE=require` and `PGPASSWORD` taken from the RDS-managed secret;
  - logs to a log group kept 7 days.
- The ECS service, with a public IP and the API's security group.
- The task execution role and the task role.
- The load balancer, its listener on port 80, and its target group: health check on `/api/health`, matcher `200,503`.
- The private web bucket, with origin access control.
- CloudFront:
  - the default behavior goes to the bucket, with default root object `index.html`;
  - `/api/*` goes to the load balancer, with caching disabled;
  - HTTP redirects to HTTPS.
- The outputs CD needs: `url`, `web_bucket`, `distribution_id`, `ecr_repository_url`, `ecs_cluster`, `ecs_service`.
- Their tests.

**Out of scope:**

- Building or pushing images, and publishing the web build (slice 06).
- The workflows (slices 05 and 06).
- Any apply.

### Acceptance criteria

| ID  | Criterion | Verified by |
| --- | --------- | ----------- |
| AC1 | `/api/*` goes to the load balancer origin with caching disabled, every other path goes to the bucket origin, and HTTP redirects to HTTPS | run `routes_api_to_alb` in `src/infra/envs/production/tests/routing.tftest.hcl`, via `make check-infra` |
| AC2 | The target group checks `/api/health` and counts 200 and 503 as healthy | run `health_check_accepts_503` in `src/infra/envs/production/tests/routing.tftest.hcl`, via `make check-infra` |
| AC3 | The task runs the `live` image on port 8080, with `PGHOST` from RDS, `PGSSLMODE=require`, and `PGPASSWORD` from the RDS-managed secret | run `task_uses_live_image_and_database` in `src/infra/envs/production/tests/compute.tftest.hcl`, via `make check-infra` |
| AC4 | The web bucket is deleted together with its files, blocks all public access, and only the distribution can read it | run `bucket_is_private_and_destroyable` in `src/infra/envs/production/tests/destroy.tftest.hcl`, via `make check-infra` |
| AC5 | The load balancer has no deletion protection, and this root manages the log group | run `edge_is_destroyable` in `src/infra/envs/production/tests/destroy.tftest.hcl`, via `make check-infra` |
| AC6 | The outputs CD needs exist | run `outputs_for_cd` in `src/infra/envs/production/tests/compute.tftest.hcl`, via `make check-infra` |
| AC7 | Format, validate and every Terraform test pass | `make check-infra` |
| AC8 | The plan of this PR deletes and replaces nothing | the `terraform` check of this PR is green, and its log shows `plan-guard: ok`: `gh pr checks <pr>` |

## Slice 05 — Destroy workflow

**Goal:** production can be destroyed in one approved run that leaves the bootstrap intact.

**Requirements:** Destroy on demand, One production run at a time, Bootstrap stays protected

**Scope:** `.github/workflows/destroy.yml`:

- `workflow_dispatch` only;
- the concurrency group `production`, with `cancel-in-progress: false`;
- job `plan`:
  - the plan role through OIDC;
  - `terraform plan -destroy -out`;
  - the plan text in the run summary;
  - the saved plan uploaded as an artifact;
- job `destroy`:
  - environment `production`, the deploy role;
  - applies that saved plan;
  - then fails unless `terraform state list` prints nothing and `aws s3api head-bucket` finds the state bucket.

**Out of scope:**

- Running it: its first runs are slice 07's.
- `cd.yml` and `verify.yml` (slice 06).

### Acceptance criteria

| ID  | Criterion | Verified by |
| --- | --------- | ----------- |
| AC1 | The workflow is valid | `docker run --rm -v "$PWD":/repo -w /repo rhysd/actionlint:1.7.7 .github/workflows/destroy.yml` prints nothing and exits 0 |
| AC2 | Only a manual dispatch starts it, and only the `destroy` job runs in `production`, after `plan` | `grep -nE '^on:\|workflow_dispatch\|environment:\|needs:' .github/workflows/destroy.yml` shows `workflow_dispatch` as the only trigger, `environment: production` only on `destroy`, and `needs: plan` |
| AC3 | `plan` uses the plan role, and `destroy` uses the deploy role | `grep -n 'role-to-assume' .github/workflows/destroy.yml` shows `vars.AWS_PLAN_ROLE_ARN` in `plan` and `vars.AWS_DEPLOY_ROLE_ARN` in `destroy` |
| AC4 | `destroy` applies the saved destroy plan of `plan` | `grep -nE 'plan -destroy\|apply' .github/workflows/destroy.yml` shows `plan -destroy -out` in `plan` and an apply of that file in `destroy` |
| AC5 | After the apply, the job fails unless the state is empty and the state bucket exists | `grep -nE 'state list\|head-bucket' .github/workflows/destroy.yml` shows both checks in `destroy`, after the apply |
| AC6 | It shares the group `production` and never cancels a run in progress | `grep -nA2 '^concurrency:' .github/workflows/destroy.yml` shows `group: production` and `cancel-in-progress: false` |
| AC7 | CI stays green | `gh pr checks <pr>` |

## Slice 06 — CD and post-deploy verification

**Goal:** a merge that changes the app deploys it to production after approval, then verifies the live site.

**Requirements:** Continuous deployment, Post-deploy verification, One production run at a time

**Scope:**

- `.github/workflows/cd.yml`:
  - triggers: a push to main with the paths `src/api/**`, `src/web/**`, `src/infra/envs/**` and `.github/workflows/cd.yml`, and `workflow_dispatch`;
  - the concurrency group `production`, with `cancel-in-progress: false`;
  - job `plan`: the plan role, `plan -out`, the plan text in the run summary, plan-guard, the saved plan as an artifact;
  - job `deploy`, in environment `production`, with the deploy role:
    1. apply the saved plan;
    2. build and push the API image as `:<sha>` and `:live`;
    3. `aws ecs update-service --force-new-deployment`, and wait until the service is stable;
    4. build the web, sync it to the bucket, invalidate CloudFront and wait;
  - job `verify`, calling `verify.yml`.
- `.github/workflows/verify.yml`:
  - `workflow_call` and `workflow_dispatch`;
  - the plan role, with the URL from `terraform output -raw url`;
  - `src/e2e/scripts/check-health.sh`, then `make e2e` with `BASE_URL` set to the URL;
  - the URL in the run summary.
- `src/e2e/scripts/check-health.sh`: given a base URL, it retries `GET /api/health` until it answers 200 with database ok, for at most `VERIFY_TIMEOUT` seconds (default 300).

**Out of scope:**

- Running the round trip (slice 07).
- Automatic rollback.

### Acceptance criteria

| ID  | Criterion | Verified by |
| --- | --------- | ----------- |
| AC1 | Both workflows are valid | `docker run --rm -v "$PWD":/repo -w /repo rhysd/actionlint:1.7.7 .github/workflows/cd.yml .github/workflows/verify.yml` prints nothing and exits 0 |
| AC2 | `cd.yml` runs on a push to main that touches the four paths, and on dispatch, and on nothing else | `grep -nA8 '^on:' .github/workflows/cd.yml` shows `push` to `main` with exactly those four paths, and `workflow_dispatch` |
| AC3 | Only `deploy` runs in `production`, after `plan`, and `plan` runs plan-guard | `grep -nE 'environment:\|needs:\|plan-guard' .github/workflows/cd.yml` |
| AC4 | `cd.yml` shares the group `production` and never cancels a run in progress | `grep -nA2 '^concurrency:' .github/workflows/cd.yml` shows `group: production` and `cancel-in-progress: false` |
| AC5 | `verify.yml` can be called by `cd.yml` and dispatched by hand, and `cd.yml` calls it after `deploy` | `grep -nE 'workflow_call\|workflow_dispatch' .github/workflows/verify.yml`, and `grep -n 'verify.yml' .github/workflows/cd.yml` |
| AC6 | The health check passes on a healthy site | `make up`, then `src/e2e/scripts/check-health.sh http://localhost:3000` exits 0 |
| AC7 | The health check fails on an unhealthy site within its time limit | `docker compose stop db`, then `VERIFY_TIMEOUT=10 src/e2e/scripts/check-health.sh http://localhost:3000` exits non-zero in about 10 seconds; then `make up` |
| AC8 | The suite runs against a URL given in `BASE_URL`, as `verify.yml` runs it | `BASE_URL=http://localhost:3000 make e2e` passes |
| AC9 | CI stays green | `gh pr checks <pr>` |

## Slice 07 — Round trip

**Goal:** real runs prove that the code on main deploys, verifies and destroys production cleanly, and the change is archived.

**Requirements:** Continuous deployment, Post-deploy verification, Destroy on demand, Destroy-ready resources, Bootstrap stays protected, Single HTTPS origin

**Scope:** no workflow or infrastructure code.

Claude dispatches each run with `gh workflow run`. Cristian approves the command, and approves the `production` environment in GitHub. The runs, in order:

1. the first `cd.yml` run, triggered by the merge of slice 06 (linked, not dispatched);
2. `destroy.yml`;
3. `cd.yml` by dispatch, from nothing;
4. `verify.yml` by dispatch;
5. `destroy.yml` again.

Then:

- add `docs/production.md`: how to deploy, verify and destroy, and what each run shows;
- merge the delta specs into `openspec/specs/`, and archive the change.

**Out of scope:**

- Any change to `.github/workflows/` or `src/infra/`.
- If a run fails, the slice stops. Its report gives the failing run's link and the relevant log lines, and Cristian decides the fix.

### Acceptance criteria

| ID  | Criterion | Verified by |
| --- | --------- | ----------- |
| AC1 | The `cd.yml` run from the merge of slice 06 deployed and verified production | `gh run view <run-id>`: `plan`, `deploy` and `verify` succeeded on attempt 1 |
| AC2 | The first destroy deleted all of production in one run, and left the bootstrap intact | `gh run view <run-id> --log`: `destroy` succeeded on attempt 1, the state list is empty and the state bucket exists |
| AC3 | `cd.yml` from nothing re-created production with no collision and no manual step | `gh run view <run-id>`: every job succeeded on attempt 1 |
| AC4 | The manual verification passed on the re-created site | `gh run view <run-id>` of `verify.yml`: succeeded on attempt 1 |
| AC5 | The site served the page and the API on one HTTPS address | the summaries of the runs in AC3 and AC4 show the `https://<id>.cloudfront.net` URL, with both checks passed |
| AC6 | The second destroy left production destroyed and the bootstrap intact | `gh run view <run-id> --log`: `destroy` succeeded on attempt 1, the state list is empty and the state bucket exists |
| AC7 | This slice changes no workflow or infrastructure code | `git diff --stat origin/main...HEAD -- .github src/infra` prints nothing |
| AC8 | The specs are merged and the change is archived | `make spec-lint` passes, and `openspec/specs/` has `health`, `status-page`, `local-stack`, `production` and `delivery` |
