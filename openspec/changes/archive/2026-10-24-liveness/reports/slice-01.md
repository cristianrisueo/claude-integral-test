# Slice report: liveness 01 — Liveness endpoint and load balancer check

## What was done

The API has a new endpoint, `GET /api/live`. It answers 200 with `{"status":"ok","version":"<version>"}` whenever the API is running, and it never asks the database.
The load balancer now checks `/api/live` and accepts only 200, instead of checking `/api/health` and accepting 200 or 503. AWS refused that old setting, which is why the first deploy failed.
`/api/health` is unchanged, so the page still shows "Database: unreachable" when the database is down.
This was the only slice, so the change is archived. Its two requirements are now in `openspec/specs/health/spec.md` and `openspec/specs/production/spec.md`.

Decisions made on Cristian's behalf:

- `TestLiveIgnoresDatabase` also checks that `/api/health` answers 503 against the same broken database, as the spec's "Database unreachable" scenario says.
- `TestLiveWithoutDatabase` repeats the start-up setup of `TestServerStartsWithoutDatabase` instead of sharing a helper with it, so the existing test stays untouched.
- `openspec/specs/` was empty, so both capability files are new. I wrote their Purpose paragraphs. Bootstrap's requirements join the same files when bootstrap is archived.

## How we checked it

| Criterion | Test or command | Result |
| --------- | --------------- | ------ |
| AC1: `/api/live` answers 200, the ok body, JSON and `no-store` | `TestLiveAnswersOK`, via `make test` | pass |
| AC2: 200 in under 1 second while the database refuses or never answers | `TestLiveIgnoresDatabase` (2 subtests), via `make test` | pass, 2 of 2 |
| AC3: reports the build version | `TestLiveReportsVersion`, via `make test` | pass |
| AC4: the server started with no database answers 200 on `/api/live` | `TestLiveWithoutDatabase`, via `make test` | pass |
| AC5: the target group checks `/api/live` with `200`, and its wiring is unchanged | run `health_check_uses_live`, via `make check-infra` | pass, 10 of 10 runs |
| AC6: the local stack serves `/api/live` through `web` | `make up`, then `make e2e` | pass, 3 of 3 tests |
| AC7: with the database stopped, `/api/live` is 200 and `/api/health` is 503 | `docker compose stop db`, then `curl` both, then `make up` | pass: 200 and 503; after `make up`, 200 and 200 |
| AC8: the plan of this PR deletes and replaces nothing | the `terraform` check of this PR (`gh pr checks <pr>`, log shows `plan-guard: ok`) | runs in CI on this PR |
| AC9: format, lint, unit, Terraform and end-to-end checks pass | `make check`, `make test`, `make check-infra`, `make e2e` | pass, all four |

## Check it yourself

1. `make up && curl -s http://localhost:3000/api/live`: prints `{"status":"ok","version":"dev"}`.
2. `docker compose stop db && curl -s -o /dev/null -w '%{http_code}\n' http://localhost:3000/api/live`: prints `200` while the database is stopped. Run `make up` afterwards.
3. `make check-infra`: ends with `Success! 10 passed, 0 failed.`, including `run "health_check_uses_live"... pass`.
