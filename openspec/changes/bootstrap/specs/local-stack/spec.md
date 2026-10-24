# Local stack — delta for bootstrap

## ADDED Requirements

### Requirement: Local stack

`make up` SHALL start the whole application under docker compose:

- `db`: PostgreSQL 17;
- `api`: the API, built from the same Dockerfile that ships, on http://localhost:8080;
- `web`: the web page, with `/api/` proxied to `api`, on http://localhost:3000.

`make down` MUST keep the database volume.

#### Scenario: Start the stack

- **WHEN** `make up` finishes
- **THEN** http://localhost:3000 shows "API: ok" and "Database: ok"
- **AND** `GET http://localhost:3000/api/health` responds 200 with `{"status":"ok","database":"ok","version":"dev"}`

#### Scenario: Database stopped

- **WHEN** the `db` service is stopped while `api` and `web` run
- **THEN** `GET http://localhost:3000/api/health` responds 503 with `{"status":"unavailable","database":"unreachable","version":"dev"}`

#### Scenario: Data survives a restart

- **WHEN** `make down` runs and then `make up` runs
- **THEN** the database volume still exists, with its data

### Requirement: End-to-end suite

`make e2e` SHALL run the Playwright suite in `src/e2e/` against the URL in `BASE_URL`, or against http://localhost:3000 when `BASE_URL` is not set.
The suite MUST check both the page and `GET /api/health`.

#### Scenario: Against the local stack

- **WHEN** `make up` has finished and `make e2e` runs without `BASE_URL`
- **THEN** the suite passes: the page shows "API: ok" and "Database: ok"
- **AND** `/api/health` responds 200 with `{"status":"ok","database":"ok","version":"dev"}`

#### Scenario: Against another URL

- **WHEN** `make e2e` runs with `BASE_URL` set
- **THEN** every test targets that URL, and none targets localhost
