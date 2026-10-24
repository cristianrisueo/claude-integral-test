# Health — delta for bootstrap

## ADDED Requirements

### Requirement: Health check

The API SHALL answer `GET /api/health` with a JSON body that reports whether PostgreSQL answers a ping within 2 seconds.
Every response MUST carry `Content-Type: application/json` and `Cache-Control: no-store`.
The response MUST NOT include the database error, which SHALL go only to the logs.

#### Scenario: Database reachable

- **WHEN** `GET /api/health` is called and PostgreSQL answers the ping
- **THEN** the API responds 200 with `{"status":"ok","database":"ok"}`
- **AND** the response carries `Content-Type: application/json` and `Cache-Control: no-store`

#### Scenario: Database unreachable

- **WHEN** `GET /api/health` is called and PostgreSQL cannot be reached or does not answer within 2 seconds
- **THEN** the API responds 503 with `{"status":"unavailable","database":"unreachable"}` in under 3 seconds
- **AND** the body holds no error detail, and the error is logged

### Requirement: Start without the database

The API MUST start and serve `/api/health` while PostgreSQL is unreachable.
It SHALL report the database as ok as soon as the database answers again, without a restart.

#### Scenario: Start with the database down

- **WHEN** the API starts and PostgreSQL is unreachable
- **THEN** it listens on port 8080 and `GET /api/health` responds 503

#### Scenario: Database comes back

- **WHEN** PostgreSQL becomes reachable while the API is running
- **THEN** the next `GET /api/health` responds 200, with no restart of the API

### Requirement: Database settings from the environment

The API SHALL read its PostgreSQL connection settings only from the standard variables `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`, `PGDATABASE` and `PGSSLMODE`.
It SHALL listen on port 8080.

#### Scenario: Settings from the variables

- **WHEN** the API starts with the `PG*` variables pointing at a database
- **THEN** it connects to that host, port, database and user, with that TLS mode
- **AND** it reads no connection setting from a file or a flag
