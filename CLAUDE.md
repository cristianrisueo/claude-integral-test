# claude-integral-test

## Project

A users CRUD (create, read, update, delete; no login) with a web UI, deployed to AWS end to end. The folders are:
`api/` (the Go backend: `net/http`, `pgx`, `golang-migrate`),
`web/` (React + Vite + TypeScript),
`e2e/` (Playwright),
`infra/` (Terraform for `eu-west-1`: ECS Fargate + ALB, RDS, ECR, S3 + CloudFront, with `/api/*` routed to the backend),
`openspec/` (the specs and the changes in flight) and
`tools/` (the harness tools).
PostgreSQL runs under `docker compose` locally and on RDS in production. `api/`, `web/`, `e2e/` and `infra/` do not exist until a change creates them; the Makefile prints a skip for whatever is missing.

## How we work

Every piece of work is a change in `openspec/changes/<id>/`, built one slice at a time:

| Skill                    | Runs                     | Does                                                                                          |
| ------------------------ | ------------------------ | --------------------------------------------------------------------------------------------- |
| `/propose <id> [idea]`   | locally, on `main`       | Interviews Cristian, writes the change, opens the `propose/<id>` PR                           |
| `/build <id> <NN>`       | locally                  | Builds one slice tests-first and opens `feat/<id>-<NN>`; rerun for the one fix round          |
| `/audit <pr>`            | in CI only, never locally | Read-only verdict comment on `feat/*` PRs                                                     |
| `/ship <pr>`             | locally                  | Waits for checks (and the verdict on `feat/*`), shows the slice report, the proposal or a `chore/*` PR's description, asks Cristian, squash-merges |

- One slice per session.
- Work always starts in plan mode: present the plan and wait for approval before editing.
- State lives in files (the change, its slices, their reports), not in the conversation.

## Commands

Use these verbs. Never call the underlying tool directly when a verb exists.

| Verb                    | Runs                                                                                                          |
| ----------------------- | ------------------------------------------------------------------------------------------------------------- |
| `make check`            | `make harness-test`, then `gofmt -l` + `go vet` (api), `npm run lint` + `typecheck` (web), `terraform fmt -check` + `validate` (infra) |
| `make test`             | `go test -race -count=1 ./...` (api), `npm test -- --run` (web)                                               |
| `make e2e`              | Playwright in `e2e/` against the local stack                                                                  |
| `make up` / `make down` | `docker compose up -d --wait` / `docker compose down` (never `-v`)                                            |
| `make harness-test`     | Tests of the hooks, `change-guard`, `plan-guard` and `spec-lint`                                              |
| `make spec-lint`        | Lints `openspec/`                                                                                             |

## Specs

- `openspec/specs/<capability>/spec.md` is what the system does today.
- `openspec/changes/<id>/` is a change in flight; `openspec/changes/archive/` holds finished changes.
- A change's `proposal.md`, `tasks.md` and `specs/**` are immutable once merged to `main`. Only its `reports/` grows, and archiving moves the whole folder. A design change is a new change.
- Requirement names are the IDs that slices, tests and reports cite.
- If code and spec disagree, stop and say so. Never silently pick one.

## Git

- Never commit or push on `main`. It changes only through squash-merged PRs.
- Branches are `propose/<id>` for a proposal and `feat/<id>-<NN>` for a slice.
- Harness maintenance (`.claude/`, `CLAUDE.md`, `Makefile`, `tools/`, `.github/`) goes on `chore/*` branches. CI runs on them; the audit does not.
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
