# claude-integral-test

## Project

A users CRUD (create, read, update, delete; no login) with a web UI, deployed to AWS end to end. All application code lives under `src/`:
`src/api/` (the Go backend: `net/http`, `pgx`, `golang-migrate`),
`src/web/` (React + Vite + TypeScript),
`src/e2e/` (Playwright) and
`src/infra/` (Terraform for `eu-west-1`: ECS Fargate + ALB, RDS, ECR, S3 + CloudFront, with `/api/*` routed to the backend).
The harness lives beside it: `openspec/` (the specs and the changes in flight) and `tools/` (the harness tools).
PostgreSQL runs under `docker compose` locally and on RDS in production. `src/api/`, `src/web/`, `src/e2e/` and `src/infra/` do not exist until a change creates them; the Makefile prints a skip for whatever is missing. The one exception is `src/infra/bootstrap/`: the one-time state bucket and GitHub OIDC roles, applied by Cristian by hand. Never run `plan` or `apply` there.

## How we work

Every piece of work is a change in `openspec/changes/<id>/`, built one slice at a time:

| Skill                    | Runs                     | Does                                                                                          |
| ------------------------ | ------------------------ | --------------------------------------------------------------------------------------------- |
| `/propose <id> [idea]`   | locally, on `main`       | Interviews Cristian, writes the change, opens the `propose/<id>` PR                           |
| `/build <id> <NN>`       | locally                  | Builds one slice tests-first and opens `feat/<id>-<NN>`; rerun for the one fix round          |
| `/audit <pr>`            | in CI only, never locally | Read-only verdict comment on `feat/*` PRs                                                     |
| `/ship <pr>`             | locally                  | Waits for checks (and the verdict on `feat/*`), shows the slice report, the proposal or a `chore/*` PR's description, asks Cristian, squash-merges |
| `/retro <id>`            | locally, on `main`, after the change is archived | Read-only retrospective: writes `docs/retros/<id>.md`, opens the `chore/retro-<id>` PR, never changes the harness |

- One slice per session.
- Work always starts in plan mode: present the plan and wait for approval before editing.
- State lives in files (the change, its slices, their reports), not in the conversation.

## Commands

Use these verbs. Never call the underlying tool directly when a verb exists.

| Verb                    | Runs                                                                                                          |
| ----------------------- | ------------------------------------------------------------------------------------------------------------- |
| `make check`            | `make harness-test`, then `gofmt -l` + `go vet` (`src/api`), `npm run lint` + `typecheck` (`src/web`)       |
| `make check-infra`      | `terraform fmt -check`, then `init -backend=false` + `validate` in every `src/infra` folder with `.tf` files, then `terraform test` in every one with a `tests/` directory (runs outside the sandbox) |
| `make test`             | `go test -race -count=1 ./...` (`src/api`), `npm test -- --run` (`src/web`)                                   |
| `make e2e`              | Playwright in `src/e2e/` against the local stack                                                              |
| `make up` / `make down` | `docker compose up -d --wait` / `docker compose down` (never `-v`)                                            |
| `make harness-test`     | Tests of the hooks, `change-guard`, `plan-guard` and `spec-lint`                                              |
| `make spec-lint`        | Lints `openspec/`                                                                                             |

Always run terraform as `terraform init ...` or `terraform validate ...` from inside the folder, never with `-chdir`, so the sandbox exclusions match. Change into the folder with `cd` in its own call first: a call that contains `cd` stays sandboxed.

## Specs

- `openspec/specs/<capability>/spec.md` is what the system does today.
- `openspec/changes/<id>/` is a change in flight; `openspec/changes/archive/` holds finished changes.
- A change's `proposal.md`, `tasks.md` and `specs/**` are immutable once merged to `main`. Only its `reports/` grows, and archiving moves the whole folder. A design change is a new change.
- Requirement names are the IDs that slices, tests and reports cite.
- If code and spec disagree, stop and say so. Never silently pick one.

## Git

- Never commit or push on `main`. It changes only through squash-merged PRs.
- Branches are `propose/<id>` for a proposal and `feat/<id>-<NN>` for a slice.
- Harness maintenance (`.claude/`, `CLAUDE.md`, `Makefile`, `tools/`, and `.github/` except what a change may edit, below) goes on `chore/*` branches. CI runs on them; the audit does not.
- A change may edit `.github/workflows/cd.yml`, `destroy.yml`, `verify.yml` and the `checks`, `e2e` and `terraform` jobs of `ci.yml`. It never edits the harness jobs of `ci.yml` (`harness`, `spec`, `audit`), the pull request template, or anything else under `.github/`. `/audit` checks this from the diff.
- Use Conventional Commits (`feat:`, `fix:`, `test:`, `docs:`, `chore:`, `ci:`, `refactor:`). The PR title becomes the squash commit and follows the same convention.
- Never force push. Never merge except through `/ship`.

## Testing

- Write tests first. Record a red run in the PR description, failing on assertions and not on compilation, before the implementation.
- Test files that exist on `main` are never weakened or deleted. If one is wrong, report it.

## Safety

- Never run `terraform apply` or `terraform destroy` locally. Infrastructure changes go through CD, with Cristian's approval in GitHub.
- Never wipe Docker volumes (`docker compose down -v`, `docker volume rm`, `docker volume prune`).
- A hook block is final: adapt, or stop and report. Never look for another way to do the same thing.
- Never commit secrets, credentials or personal data.

## Compaction

When compacting, preserve: the change id and slice in progress, the list of modified files, the commands that verify the slice, and any open decision.
