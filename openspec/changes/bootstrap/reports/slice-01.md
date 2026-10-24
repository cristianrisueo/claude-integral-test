# Slice report: bootstrap 01 — Health endpoint on local Postgres

## What was done

There is now a Go API in `src/api/`. It answers `GET /api/health` and asks Postgres whether it is up each time it is called.
If the database answers within 2 seconds, it replies 200 with `"database":"ok"`. If not, it replies 503 with `"database":"unreachable"`.
The error itself goes only to the log, never into the reply.
The reply also carries the version the API was built from. A normal build says `dev`, and an image built with `VERSION=<sha>` says that SHA.
The API starts even when the database is down, and reports it ok again as soon as it comes back, with no restart.

`make up` now starts two containers: Postgres 17 (`db`) and the API on http://localhost:8080 (`api`).
The API runs from `src/api/Dockerfile`, the same image that will ship to AWS.

Decisions made on Cristian's behalf:

- The "database answers" and "database comes back" tests use a stand-in for the database instead of a real Postgres. CI's `checks` job has no Postgres, and adding one is outside this slice. The real database is checked on the local stack (AC7 and AC8). The "database unreachable" test uses a real connection pool, as the criterion asks.
- The 8080 test checks that the server is set to `:8080`, then runs that same server on a free port. That way `make test` still passes while `make up` holds port 8080.
- The `api` container has no health check of its own, because its minimal image has no shell or curl. `make up` waits until it is running.
- Go 1.27, the toolchain on this machine. CI reads the version from `src/api/go.mod`.

## How we checked it

| Criterion | Test or command | Result |
| --------- | --------------- | ------ |
| AC1: database answers → 200 ok, JSON, `no-store` | `TestHealthDatabaseReachable` | pass |
| AC2: database unreachable → 503, under 3 s, no error in body | `TestHealthDatabaseUnreachable` (port closed; port that never answers) | pass, 2 subtests; the silent port answers in 2.0 s |
| AC3: reports the version it is given, on 200 and 503 | `TestHealthReportsVersion` | pass |
| AC4: 200 again once the database answers, no restart | `TestHealthRecovers` | pass |
| AC5: starts and serves on 8080 with the database down | `TestServerStartsWithoutDatabase` | pass |
| AC6: settings only from `PG*` variables | `TestConfigFromEnvironment` (`disable` and `require`) | pass, 2 subtests |
| AC7: local stack reports database ok, version `dev` | `make up`, then `curl -si http://localhost:8080/api/health` | pass: `200` `{"status":"ok","database":"ok","version":"dev"}` |
| AC8: `db` stopped → unreachable | `docker compose stop db`, then the same `curl`; then `make up` | pass: `503` in 0.04 s; after `make up`, `200` again without restarting `api` |
| AC9: image built with `VERSION` reports it | `docker build --build-arg VERSION=abc1234 …`, run on 18080, `curl` | pass: `503` `"version":"abc1234"`; image is `linux/amd64` |
| AC10: format, vet and tests green | `make check`, `make test` | pass, both exit 0 |

## Check it yourself

1. `make up && curl -si http://localhost:8080/api/health`: you should see `200 OK` and `{"status":"ok","database":"ok","version":"dev"}`.
2. `docker compose stop db && curl -si http://localhost:8080/api/health; make up`: you should see `503 Service Unavailable` and `"database":"unreachable"`, and after `make up` the first command shows 200 again.
3. `make test`: you should see `ok` for `src/api/cmd/api` and `src/api/internal/health`.
