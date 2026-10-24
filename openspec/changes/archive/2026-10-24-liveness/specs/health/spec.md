# Health — delta for liveness

## ADDED Requirements

### Requirement: Liveness

The API SHALL answer `GET /api/live` with 200 and `{"status":"ok","version":"<version>"}` whenever its process can serve HTTP, where `<version>` is the build version that `/api/health` reports.
It MUST NOT contact PostgreSQL to answer.
Every response MUST carry `Content-Type: application/json` and `Cache-Control: no-store`.

#### Scenario: Database reachable

- **WHEN** `GET /api/live` is called and PostgreSQL answers
- **THEN** the API responds 200 with `{"status":"ok","version":"<version>"}`
- **AND** the response carries `Content-Type: application/json` and `Cache-Control: no-store`

#### Scenario: Database unreachable

- **WHEN** `GET /api/live` is called while PostgreSQL refuses connections or never answers
- **THEN** the API responds 200 with `{"status":"ok","version":"<version>"}` in under 1 second
- **AND** `GET /api/health` still responds 503

#### Scenario: Start with the database down

- **WHEN** the API starts while PostgreSQL is unreachable
- **THEN** `GET /api/live` on port 8080 responds 200
