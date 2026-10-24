# Slice report: bootstrap 02 — Status page and end-to-end suite

## What was done

There is now a web page in `src/web/`, built with React, Vite and TypeScript. When it loads, it calls `/api/health` on its own address and shows one of four states:

- while it waits: "Checking…";
- 200 with the "ok" body: "API: ok" and "Database: ok";
- 503 with the "unavailable" body: "API: ok" and "Database: unreachable";
- anything else (no answer, or a 502 page from a proxy): "API: unreachable" and "Database: unknown".

`make up` now starts a third container, `web`, on http://localhost:3000. It serves the page with nginx and passes `/api/` on to the API, so the page and the API share one address, as they will behind CloudFront.

`src/e2e/` holds the Playwright suite: one test opens the page, one calls `/api/health`. `make e2e` runs it against http://localhost:3000, or against `BASE_URL` when it is set. The CI `e2e` job now installs the suite and Chromium, starts the stack, runs the suite, prints the container logs if it fails, and stops the stack.

Decisions made on Cristian's behalf:

- **AC9 shows a different error for the page test.** With `BASE_URL=http://localhost:9`, both tests fail and both target port 9. But Chromium blocks port 9 outright (it is on its list of unsafe ports), so the page test says `ERR_UNSAFE_PORT` instead of "connection refused". The API test does say `ECONNREFUSED`. On a closed port Chromium allows, `BASE_URL=http://localhost:9999`, both tests say "connection refused". The code is the same either way; only the port in the criterion's command is unlucky.
- **`make up` does not rebuild images.** After changing the page, run `docker compose build web` before `make up`, or the old page keeps running. CI always builds from scratch, so it is not affected. Changing `make up` is harness work, outside this slice.
- **The web container's health check calls `127.0.0.1`, not `localhost`.** Inside the container `localhost` resolves to the IPv6 address first, and nginx listens on IPv4 only, so the check never passed.
- **Images and tools:** `node:24-alpine` to build the page and `nginx:1.29-alpine` to serve it; ESLint flat config with the TypeScript and React Hooks rules; TypeScript 6 in both `src/web` and `src/e2e`.
- **The unit tests stand in for `fetch`.** They check the page's four states without a running API. The real API is checked by the end-to-end suite.

## How we checked it

| Criterion | Test or command | Result |
| --------- | --------------- | ------ |
| AC1: "Checking…" while pending | "shows checking while the request is pending" | pass |
| AC2: calls `/api/health` on its origin; 200 → API ok, Database ok | "shows API and database ok" | pass |
| AC3: 503 → API ok, Database unreachable | "shows database unreachable on 503" | pass |
| AC4: failed request → API unreachable, Database unknown | "shows API unreachable when the request fails" | pass |
| AC5: other response (502 HTML) → API unreachable, Database unknown | "shows API unreachable on an unexpected response" | pass |
| AC6: `web` serves the page and proxies the API | `make up`, `curl -s http://localhost:3000/api/health`, `curl -s http://localhost:3000/` | pass: `{"status":"ok","database":"ok","version":"dev"}`, and the page's HTML |
| AC7: `db` stopped → 503 through `web` | `docker compose stop db`, `curl -si http://localhost:3000/api/health`; `make up` | pass: `503 Service Unavailable`; 200 again after `make up` |
| AC8: suite passes on the local stack | `make e2e` | pass: 2 passed |
| AC9: suite targets `BASE_URL` | `BASE_URL=http://localhost:9 make e2e` | pass with a note: 2 failed, both on port 9; the API test says `ECONNREFUSED`, the page test `ERR_UNSAFE_PORT` (see above). On port 9999 both say connection refused |
| AC10: `make down` keeps the volume | `make down`, `docker volume ls`; `make up` | pass: `claude-integral-test_pgdata` still listed |
| AC11: CI `e2e` job runs the suite | the `e2e` check of this PR: `gh pr checks <pr>` | runs on this PR |
| AC12: lint, typecheck and unit tests green | `make check`, `make test` | pass, both exit 0 |

## Check it yourself

1. `docker compose build web && make up`, then open http://localhost:3000 — you should see "API: ok" and "Database: ok".
2. `docker compose stop db`, then reload the page — you should see "API: ok" and "Database: unreachable". `make up` brings it back to ok.
3. `make e2e` — you should see `2 passed`.
