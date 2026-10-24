# Delivery specification

## Purpose

How code reaches production: the checks every pull request runs in CI, the GitHub workflows that deploy, verify and destroy production after Cristian's approval, and the rule that keeps those runs from overlapping.

## Requirements

### Requirement: Plan on pull requests

The CI `terraform` job SHALL plan `src/infra/envs/production/` on every pull request.
It SHALL use the read-only plan role through OIDC.
It MUST fail when plan-guard finds a deletion or a replacement.
It SHALL publish the plan text as the `terraform-plan` artifact.

#### Scenario: Plan without deletions

- **WHEN** a pull request is opened or updated
- **THEN** the job runs `fmt -check`, `init`, `validate` and `plan`, and plan-guard prints ok
- **AND** the `terraform-plan` artifact holds the plan text

#### Scenario: Plan with a deletion

- **WHEN** the plan would delete or replace a resource
- **THEN** the `terraform` check fails and lists the addresses of those resources

### Requirement: End-to-end tests on pull requests

The CI `e2e` job SHALL start the local stack with `make up` and run `make e2e` on every pull request.
It MUST fail when a test fails.

#### Scenario: Pull request

- **WHEN** a pull request is opened or updated
- **THEN** the `e2e` job builds the stack, runs the suite and stops the stack
- **AND** when a test fails, the job prints the logs of the compose services and fails

### Requirement: Continuous deployment

`cd.yml` SHALL deploy production in two cases: on a push to main that changes `src/api/`, `src/web/`, `src/infra/envs/` or `cd.yml`, and on manual dispatch.

The `plan` job MUST plan with the read-only role, show the plan in the run summary and run plan-guard.

The `deploy` job MUST run in the `production` environment, so it starts only after Cristian approves. In order, it SHALL:

1. apply exactly the saved plan;
2. build the API image with the build argument `VERSION` set to the commit SHA being deployed, and push it tagged with that SHA and with `live`;
3. roll the ECS service and wait until it is stable;
4. publish the web build to the bucket and invalidate CloudFront;
5. call `verify.yml` with the commit SHA being deployed (`github.sha`) as the expected version.

#### Scenario: Merge that changes the app

- **WHEN** a push to main changes `src/api/`
- **THEN** the `plan` job runs, and the `deploy` job waits for approval
- **AND** after approval, `/api/health` reports the merged commit's SHA as `version`

#### Scenario: Merge that changes no app code

- **WHEN** a push to main changes only `openspec/`, `docs/` or harness files
- **THEN** `cd.yml` does not run

#### Scenario: Deploy from nothing

- **WHEN** `cd.yml` is dispatched by hand while production is destroyed
- **THEN** it creates every resource, and the API starts once its image is pushed
- **AND** the verification passes

#### Scenario: Plan with a deletion

- **WHEN** the plan would delete or replace a resource
- **THEN** the `plan` job fails, and the `deploy` job never starts

### Requirement: Post-deploy verification

`verify.yml` SHALL run as the last job of every `cd.yml` run, and on manual dispatch.
It SHALL use the read-only role, with no approval.
It SHALL read the site URL from the production state.
When `cd.yml` calls it, the expected version SHALL be the SHA that `cd.yml` passes in (`github.sha`).
When verify is dispatched by hand, ECR SHALL be the source of truth of what was deployed. The expected version SHALL be the one SHA tag that shares the digest of the `:live` image, read with the read-only role. Verify MUST fail, and say why, when `:live` has no SHA tag or more than one.
It MUST require `GET /api/health` to answer 200 with `"status":"ok"`, `"database":"ok"` and `version` equal to the expected version, within 5 minutes.
It SHALL then run the end-to-end suite against that URL.
Any failed check MUST fail the run.

#### Scenario: Healthy site

- **WHEN** verify runs, the site is healthy and reports the expected version
- **THEN** both checks pass, and the run summary shows the site URL and the live version

#### Scenario: Unhealthy site

- **WHEN** `/api/health` does not answer 200 with database ok within 5 minutes
- **THEN** the run fails, and nothing is rolled back

#### Scenario: Manual run after a merge that deployed nothing

- **WHEN** verify is dispatched by hand after a merge that did not trigger `cd.yml`, so main's HEAD is newer than the deployed commit
- **THEN** the expected version is the SHA tag of the `:live` image, and verify passes if the site runs it

#### Scenario: Live image without exactly one SHA tag

- **WHEN** verify is dispatched by hand and the `:live` image has no SHA tag, or more than one
- **THEN** the run fails before any check, and says which case it found

#### Scenario: New version never started

- **WHEN** the new task never starts, and the previous version keeps answering `/api/health` with 200 and database ok
- **THEN** the run fails within 5 minutes, and its summary shows the live and the expected version

### Requirement: Destroy on demand

`destroy.yml` SHALL run only on manual dispatch.

The `plan` job MUST produce a destroy plan with the read-only role and show it in the run summary.

The `destroy` job MUST run in the `production` environment, so it starts only after Cristian approves. It SHALL apply exactly that plan, in one run. It SHALL then fail unless the production state is empty and the state bucket still exists.

#### Scenario: Destroy a running production

- **WHEN** `destroy.yml` is dispatched and approved while production is up
- **THEN** every production resource is deleted in one run
- **AND** `terraform state list` prints nothing, and the state bucket still exists

#### Scenario: Nothing deployed

- **WHEN** `destroy.yml` is dispatched while production is already destroyed
- **THEN** the plan shows nothing to destroy, and the run succeeds

### Requirement: One production run at a time

`cd.yml` and `destroy.yml` MUST share one concurrency group, and SHALL never cancel a run in progress.

#### Scenario: Destroy during a deploy

- **WHEN** `destroy.yml` is dispatched while `cd.yml` is running
- **THEN** the destroy waits until the deploy has finished
