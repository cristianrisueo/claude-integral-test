# Tasks: liveness

## Slice 01 — Liveness endpoint and load balancer check

**Goal:** the API answers `GET /api/live` without the database, and the load balancer checks it with matcher 200, so production can be created.

**Requirements:** Liveness, Load balancer health check

**Scope:**

- `src/api/internal/health/`: a `Live(version string) http.Handler` that answers 200 with `{"status":"ok","version":"<version>"}`, `Content-Type: application/json` and `Cache-Control: no-store`, and never pings the database; its tests in a new file `live_test.go`.
- `src/api/cmd/api/main.go`: the route `GET /api/live`; a new test `TestLiveWithoutDatabase` in `main_test.go`. The existing tests are unchanged.
- `src/infra/envs/production/edge.tf`: the target group's health check uses path `/api/live` and matcher `200`; its comment explains why.
- `src/infra/envs/production/tests/routing.tftest.hcl`:
  - the run `health_check_accepts_503` becomes `health_check_uses_live`;
  - its path and matcher assertions expect `/api/live` and `200`;
  - its three wiring assertions (target group, listener, forward) are unchanged;
  - the header comment is updated.
- `src/e2e/tests/health.spec.ts`: a new test "GET /api/live answers 200", which expects the version `process.env.EXPECTED_VERSION ?? "dev"`. The existing tests are unchanged.

**Out of scope:**

- `/api/health`, the page, `check-health.sh`, `cd.yml` and `verify.yml`.
- The health check timings, a container health check, a grace period, a circuit breaker.
- Any file of `openspec/changes/bootstrap/`.

### Acceptance criteria

| ID  | Criterion | Verified by |
| --- | --------- | ----------- |
| AC1 | `/api/live` answers 200 with `{"status":"ok","version":"dev"}`, `Content-Type: application/json` and `Cache-Control: no-store` | `TestLiveAnswersOK` in `src/api/internal/health/live_test.go`, via `make test` |
| AC2 | `/api/live` answers 200 in under 1 second while the database refuses connections or never answers | `TestLiveIgnoresDatabase` in `src/api/internal/health/live_test.go`, via `make test` |
| AC3 | `/api/live` reports the build version | `TestLiveReportsVersion` in `src/api/internal/health/live_test.go`, via `make test` |
| AC4 | The server started with no reachable database answers 200 on `/api/live` | `TestLiveWithoutDatabase` in `src/api/cmd/api/main_test.go`, via `make test` |
| AC5 | The target group checks `/api/live` with matcher `200`, and its wiring is unchanged | run `health_check_uses_live` in `src/infra/envs/production/tests/routing.tftest.hcl`, via `make check-infra` |
| AC6 | The local stack serves `/api/live` through `web` | `make up`, then `make e2e`: "GET /api/live answers 200" in `src/e2e/tests/health.spec.ts` passes |
| AC7 | With the database stopped, `/api/live` stays 200 while `/api/health` answers 503 | `docker compose stop db`, then `curl -s -o /dev/null -w '%{http_code}' http://localhost:3000/api/live` prints `200` and the same for `/api/health` prints `503`; then `make up` |
| AC8 | The plan of this PR deletes and replaces nothing | the `terraform` check of this PR is green, and its log shows `plan-guard: ok`: `gh pr checks <pr>` |
| AC9 | Format, lint, unit, Terraform and end-to-end checks pass | `make check`, `make test`, `make check-infra` and `make e2e` |
