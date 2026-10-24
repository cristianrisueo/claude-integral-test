# Status page — delta for bootstrap

## ADDED Requirements

### Requirement: Show the health status

The web page SHALL call `GET /api/health` on its own origin when it loads.
It SHALL show exactly one of four states: checking, all ok, database unreachable, or API unreachable.

#### Scenario: Checking

- **WHEN** the page has loaded and the health response has not arrived yet
- **THEN** the page shows "Checking…"

#### Scenario: All ok

- **WHEN** the API responds 200 with `"status":"ok"` and `"database":"ok"`
- **THEN** the page shows "API: ok" and "Database: ok"

#### Scenario: Database unreachable

- **WHEN** the API responds 503 with `"status":"unavailable"` and `"database":"unreachable"`
- **THEN** the page shows "API: ok" and "Database: unreachable"

#### Scenario: API unreachable

- **WHEN** the request fails, or the response is neither of the two health bodies (for example a 502 page from the load balancer)
- **THEN** the page shows "API: unreachable" and "Database: unknown"
