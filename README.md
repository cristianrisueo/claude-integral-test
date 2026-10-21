# claude-integral-test

A users CRUD application (create, read, update and delete users; no login) with a web UI, deployed to AWS end to end. It is built almost entirely by Claude Code, under rules that keep the important decisions with people and deterministic checks.

## Stack

| Piece            | Choice                                                                                            |
| ---------------- | ------------------------------------------------------------------------------------------------- |
| Backend          | Go, standard library `net/http`, `pgx`, `golang-migrate` (`api/`)                                 |
| Frontend         | React + Vite + TypeScript (`web/`)                                                                |
| End-to-end tests | Playwright (`e2e/`)                                                                               |
| Database         | PostgreSQL: `docker compose` locally, RDS in production                                           |
| Infrastructure   | Terraform (`infra/`), AWS `eu-west-1`: ECS Fargate + ALB, RDS, ECR, S3 + CloudFront               |
| CI/CD            | GitHub Actions, authenticated to AWS through OIDC (no stored keys)                                |

The application folders are created by the changes that build them. Until then, `make` skips them.

## How this repository is built

Work happens in **changes**. A change is a folder under `openspec/changes/<id>/` that holds:

- why the change exists (`proposal.md`);
- how it will be built (`design.md`);
- what the system must do afterwards (`specs/`, written as requirements with WHEN/THEN scenarios);
- the plan, split into **slices** (`tasks.md`). Each slice is a piece small enough to review in one sitting, with acceptance criteria that name the test proving each one.

A change moves through five steps:

1. **Propose.** Claude interviews the owner about the decisions that are expensive to change later, then writes the change and opens a pull request. Nothing is built until the owner merges it.
2. **Build, one slice at a time.** In a fresh session, Claude:
   - plans the slice, and waits for the owner's approval;
   - writes the tests first and shows them failing;
   - implements the minimum to make them pass;
   - runs every check;
   - writes a report: what changed, how it was tested, what it decided on the owner's behalf, and three commands to verify it by hand.
3. **Check.** On the slice's pull request, GitHub Actions runs deterministic checks: harness tests, spec lint, linters, unit and end-to-end tests, and the Terraform plan. Then a read-only Claude audit compares the code with the change's requirements and posts a verdict. The audit allows at most one fix round.
4. **Ship.** Claude merges the pull request only after the checks are green and the audit approves, and only after the owner explicitly says yes.
5. **Deploy.** Applying infrastructure needs the owner's approval in GitHub. Claude never applies or destroys infrastructure.

When the last slice merges, the change is archived and `openspec/specs/` describes the system as it now is.

Three things are never left to the model's goodwill: finishing with failing tests, destroying infrastructure or data, and merging without the owner's approval. Each is enforced by a hook in `.claude/hooks/`, a permission rule in `.claude/settings.json`, or GitHub branch protection.

## Commands

Run `make` to list the commands. The main ones are `make check`, `make test`, `make e2e`, `make up` and `make down`.
