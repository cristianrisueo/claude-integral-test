# Proposal: liveness

## What we'll build

A second endpoint, `GET /api/live`, that answers 200 whenever the API is running, without asking the database.
The load balancer checks it instead of `/api/health`.
This unblocks the first deploy: AWS refused to create the load balancer's health check, because a check cannot count 503 as healthy.

## What you'll see when it's done

- `GET /api/live` answers `{"status":"ok","version":"<version>"}` with 200, even while the database is down.
- `GET /api/health` is unchanged. The page and verify still use it, so a database outage still shows as "Database: unreachable".
- In AWS, the load balancer checks `/api/live` and accepts only 200.
- The merge of this change starts `cd.yml`. That run finishes creating production, which the failed first deploy left half built.

## How we'll know it works

- `make test`: `/api/live` answers 200 with the version, both with the database up and with it unreachable.
- `make check-infra`: a Terraform test shows the load balancer checks `/api/live` with 200.
- `make e2e`: the end-to-end suite also checks `/api/live` on the local stack.
- With the local database stopped, `/api/live` still answers 200 and `/api/health` answers 503.
- The plan of this change's pull request deletes and replaces nothing.

## Decisions

- **Two endpoints instead of one.**
  - Bootstrap had the load balancer count both 200 and 503 as healthy. AWS only accepts codes from 200 to 499 there, so the first deploy failed.
  - `/api/live` only says the process is up. `/api/health` keeps reporting the database.
  - A database outage then never makes AWS restart the API in a loop. That was the reason for the old design.
- **`/api/live` reports the version too.** It costs nothing. It also shows what a task runs, even while the database is down.
- **Same headers as `/api/health`:** JSON, and never cached.
- **One Terraform test on main is rewritten.** The test that expected the check to accept 503 now expects `/api/live` and 200. It described something AWS refuses, so this change approves the edit. Its other checks, on the load balancer's wiring, stay as they are.
- **The health check keeps AWS's default timings.** That means a check every 30 seconds, 5 passes to become healthy and 2 failures to become unhealthy.
- **No health check inside the container.** The image has no shell and no curl, so the load balancer's check is the only one.
- **The specs only add requirements.** The bootstrap specs are not yet merged into `openspec/specs/`, so this change does not rewrite any of them. That way, it does not matter which change is archived first.

## Out of scope

- Any change to `/api/health`, the page or `verify.yml`.
- Bootstrap's own files. They are frozen. Its last slice will decide how to count the failed first deploy.
- A start-up grace period or an automatic rollback for the API service.
