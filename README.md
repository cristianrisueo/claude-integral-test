# claude-integral-test

A users CRUD application (create, read, update and delete users; no login) with a web UI, deployed to AWS end to end. It is built almost entirely by Claude Code, under rules that keep the important decisions with people and deterministic checks.

## Stack

| Piece            | Choice                                                                                            |
| ---------------- | ------------------------------------------------------------------------------------------------- |
| Backend          | Go, standard library `net/http`, `pgx`, `golang-migrate` (`src/api/`)                             |
| Frontend         | React + Vite + TypeScript (`src/web/`)                                                            |
| End-to-end tests | Playwright (`src/e2e/`)                                                                           |
| Database         | PostgreSQL: `docker compose` locally, RDS in production                                           |
| Infrastructure   | Terraform (`src/infra/`), AWS `eu-west-1`: ECS Fargate + ALB, RDS, ECR, S3 + CloudFront           |
| CI/CD            | GitHub Actions, authenticated to AWS through OIDC (no stored keys)                                |

The application folders are created by the changes that build them. Until then, `make` skips them.

## What's in this repository

| Folder      | What it holds                                                                 | Who uses it                     |
| ----------- | ----------------------------------------------------------------------------- | ------------------------------- |
| `.claude/`  | Claude Code settings, skills, hooks and templates                             | Claude, in every session        |
| `.github/`  | The CI workflow and the pull request template                                 | GitHub Actions, every PR        |
| `openspec/` | What the app does today, and the changes in progress                          | The owner and Claude            |
| `tools/`    | Deterministic checks: spec lint, change guard, plan guard                     | `make`, Claude's hooks and CI   |
| `src/`      | The application: backend, frontend, end-to-end tests and infrastructure       | Created by later changes        |

`src/` holds four folders, each created by the change that builds it:

- `src/api/`: the Go backend and its database migrations;
- `src/web/`: the React frontend;
- `src/e2e/`: the Playwright end-to-end tests;
- `src/infra/`: the Terraform for AWS.

**`.claude/`** holds `settings.json` (permissions, the sandbox and the hooks), the four skills (`/propose`, `/build`, `/audit`, `/ship`), the hooks that block what must never happen (a commit on `main`, a force push, `terraform apply`, wiping the database) and the templates the skills fill in.

**`openspec/`** has three parts. `specs/` is what the app does today. `changes/` holds the changes in progress. `changes/archive/` holds the finished ones.

**`tools/`** holds the deterministic checks, run both locally and in CI. They live outside `.github/` so the same script runs on your machine, in Claude's hooks and in CI.

## How this repository is built

Work happens in **changes**. A change is a folder under `openspec/changes/<id>/` that holds:

- the proposal (`proposal.md`): what we'll build, what you'll see, how we'll know it works, the decisions and what is out of scope;
- what the system must do afterwards (`specs/`, written as requirements with WHEN/THEN scenarios);
- the plan, split into **slices** (`tasks.md`). Each slice is a piece small enough to review in one sitting, with acceptance criteria that name the test proving each one.

The owner reads two documents: the **proposal**, to approve a change, and the **slice report**, to approve each merge.

A change moves through five steps:

1. **Propose.** Claude interviews the owner about the decisions that are expensive to change later, then writes the change and opens a pull request. Nothing is built until the owner reads the proposal and merges it.
2. **Build, one slice at a time.** In a fresh session, Claude:
   - plans the slice, and waits for the owner's approval;
   - writes the tests first and shows them failing;
   - implements the minimum to make them pass;
   - runs every check;
   - opens a pull request whose description holds the red and green test runs;
   - writes the slice report: what was done and what it decided on the owner's behalf, how each criterion was checked, and three commands to check it by hand.
3. **Check.** On the slice's pull request, GitHub Actions runs deterministic checks: harness tests, spec lint, linters, unit and end-to-end tests, and the Terraform plan. Then a read-only Claude audit compares the code with the change's requirements and posts a verdict. The audit allows at most one fix round.
4. **Ship.** Claude shows the owner the slice report and the audit verdict. It merges the pull request only after the checks are green and the audit approves, and only after the owner explicitly says yes.
5. **Deploy.** Applying infrastructure needs the owner's approval in GitHub. Claude never applies or destroys infrastructure.

When the last slice merges, the change is archived and `openspec/specs/` describes the system as it now is.

Three things are never left to the model's goodwill: finishing with failing tests, destroying infrastructure or data, and merging without the owner's approval. Each is enforced by a hook in `.claude/hooks/`, a permission rule in `.claude/settings.json`, or GitHub branch protection.

## Commands

Run `make` to list the commands. The main ones are `make check`, `make test`, `make e2e`, `make up` and `make down`.
