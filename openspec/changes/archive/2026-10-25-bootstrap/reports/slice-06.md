# Slice report: bootstrap 06 — CD and post-deploy verification

## What was done

There are now two new workflows. Nothing has run in AWS yet: the first runs are slice 07's, starting with the merge of this PR.

- **`cd.yml` deploys production.** It runs when a push to main changes `src/api`, `src/web`, `src/infra/envs` or `cd.yml`, or when you start it by hand.
  - **`plan`** uses the read-only role. It shows the plan in the run summary, runs plan-guard, and saves the plan file.
  - **`deploy`** waits for your approval in the `production` environment. Then it applies that saved plan and builds the API image with the commit SHA baked in. It pushes the image as `:<sha>` and `:live`, restarts the service and waits until it is stable. Last, it publishes the web build and clears the CloudFront cache.
  - **`verify`** calls `verify.yml` with the commit just deployed.
- **`verify.yml` checks the live site.** It only reads, so it needs no approval. You can also start it by hand.
  - It reads the site's address from the production state.
  - When `cd.yml` calls it, it expects the commit `cd.yml` passed. When you start it by hand, it asks ECR which commit the `:live` image was built from.
  - It waits up to 5 minutes for `/api/health` to answer ok on that version. Then it runs the end-to-end tests against the site.
  - The run summary shows the address, the live version and the expected version.
- **Two scripts** in `src/e2e/scripts/` do the checking. `check-health.sh` waits for the right version. `live-version.sh` finds the one commit SHA tag of `:live`, and fails if there is none or more than one.

`cd.yml` shares the `production` group with `destroy.yml`, so a deploy and a destroy never overlap.

Decisions made on Cristian's behalf:

- **The e2e test now accepts the deployed version (you approved this in the session).** `health.spec.ts` expected `version: "dev"`, so running it against production would always fail. It now expects `EXPECTED_VERSION`, or `dev` when that is not set. `verify.yml` sets it to the expected SHA. The local check is exactly as before, and the production check is stricter.
- **Verify decides "by hand or called" from its input, not from the event.** Inside a called workflow, the event is the caller's. If `cd.yml` were started by hand, verify would wrongly read ECR instead of using the commit `cd.yml` passed in.
- **Verify has no concurrency group.** It only reads. It also runs inside a `cd.yml` run that already holds the `production` group.
- **The saved plan is kept for 1 day,** as in `destroy.yml`, because the repository is public.
- **ECR login uses the AWS CLI,** not an extra action. That means one less third-party action with access to the deploy role.
- **The health check tries every 5 seconds.** Each request times out after 5 seconds.

## How we checked it

| Criterion | Test or command | Result |
| --------- | --------------- | ------ |
| AC1: both workflows are valid | `docker run --rm -v "$PWD":/repo -w /repo rhysd/actionlint:1.7.7 .github/workflows/cd.yml .github/workflows/verify.yml` | pass: no output, exit 0 |
| AC2: push to main on the four paths, and dispatch, only | `grep -nA8 '^on:' .github/workflows/cd.yml` | pass: `push`, `branches: [main]`, exactly the four paths, `workflow_dispatch` |
| AC3: only `deploy` in `production`, after `plan`; `plan` runs plan-guard | `grep -nE 'environment:\|needs:\|plan-guard' .github/workflows/cd.yml` | pass: plan-guard (line 63, `plan`); `needs: plan` (78) and `environment: production` (82), both in `deploy`; `needs: deploy` (157, `verify`) |
| AC4: group `production`, never cancels | `grep -nA2 '^concurrency:' .github/workflows/cd.yml` | pass: `group: production`, `cancel-in-progress: false` |
| AC5: verify is callable and dispatchable; cd calls it after deploy | `grep -nE 'workflow_call\|workflow_dispatch' .github/workflows/verify.yml`, `grep -n 'verify.yml' .github/workflows/cd.yml` | pass: both triggers (lines 10, 16); `uses: ./.github/workflows/verify.yml` (161) |
| AC6: image built with the SHA, same SHA passed to verify | `grep -nE 'VERSION=\|expected_version' .github/workflows/cd.yml` | pass: `VERSION=${{ github.sha }}` (124, `deploy`); `expected_version: ${{ github.sha }}` (163, `verify`) |
| AC7: by hand, the expected version comes from ECR | `grep -nE 'expected_version\|describe-images\|live-version' .github/workflows/verify.yml` | pass: the `workflow_call` input (12); `describe-images … imageTag=live \| src/e2e/scripts/live-version.sh` (66) |
| AC8: one SHA tag prints it | `src/e2e/scripts/live-version.sh < src/e2e/scripts/testdata/one-sha.json` | pass: prints `4b825dc…4904`, exit 0 |
| AC9: no SHA tag fails and says so | `… < testdata/no-sha.json` | pass: "the :live image has no SHA tag", exit 1 |
| AC10: two SHA tags fails and lists them | `… < testdata/two-shas.json` | pass: "has 2 SHA tags:" and both SHAs, exit 1 |
| AC11: healthy site on the expected version passes | `make up`, then `src/e2e/scripts/check-health.sh http://localhost:3000 dev` | pass: exit 0 |
| AC12: unhealthy site fails in time | `docker compose stop db`, then `VERIFY_TIMEOUT=10 … dev`; then `make up` | pass: exit 1 after 10 s |
| AC13: another version fails and names both | `VERIFY_TIMEOUT=10 … abc1234` | pass: exit 1 after 10 s; prints live `dev`, expected `abc1234` |
| AC14: the suite runs against `BASE_URL` | `BASE_URL=http://localhost:3000 make e2e` | pass: 2 passed. Also, with `EXPECTED_VERSION=abc1234` the health test fails on its version check |
| AC15: CI stays green | `gh pr checks <pr>` | checked on this PR; `/ship` waits for every check to be green before it asks you |

`make check` (harness tests: 105 passed, 0 failed; lint and typecheck clean), `make test` (Go: 2 packages ok; web: 5 passed) and `make e2e` (2 passed) are green. `make check-infra` was not run, because nothing in `src/infra/` changed.

## Check it yourself

1. `src/e2e/scripts/live-version.sh < src/e2e/scripts/testdata/two-shas.json` — fails, says `:live` has 2 SHA tags, and lists them.
2. `make up`, then `VERIFY_TIMEOUT=10 src/e2e/scripts/check-health.sh http://localhost:3000 abc1234` — after about 10 seconds it fails, showing `dev` as the live version and `abc1234` as the expected one.
3. `grep -nE 'environment:|needs:|plan-guard' .github/workflows/cd.yml` — plan-guard in `plan`, then `needs: plan` and `environment: production` in `deploy`, then `needs: deploy` in `verify`.
