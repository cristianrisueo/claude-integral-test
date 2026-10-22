# Harness spec — claude-integral-test

> **What this is.** The blueprint for the files that govern how Claude Code works
> in this repository: instructions, skills, hooks, permissions, scripts and CI.
> It is implemented once, on the branch `feat/harness-skeleton`, and **deleted
> right after that PR is merged** (git history keeps it).
>
> **Who reads it.** Claude Code, to build the harness; the CI auditor, to check
> the PR against it; Cristian, to approve it.

## 0. Context

### 0.1 The project

A users CRUD (create, read, update, delete; no login) with a web UI, deployed to
AWS end to end. Later changes build it; **this change builds no application
code.**

| Piece            | Decision                                                                                                                            |
| ---------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| Backend          | Go, standard library `net/http`, `pgx`, `golang-migrate` — in `api/`                                                                |
| Frontend         | React + Vite + TypeScript — in `web/`                                                                                               |
| End-to-end tests | Playwright — in `e2e/`                                                                                                              |
| Database         | PostgreSQL (RDS in production, `docker compose` locally)                                                                            |
| Infrastructure   | Terraform — in `infra/`; AWS region `eu-west-1`; ECS Fargate + ALB, RDS, ECR, S3 + CloudFront (`/api/*` routed to the backend)      |
| CI/CD            | GitHub Actions; GitHub → AWS through OIDC, no stored keys                                                                           |
| Git              | Trunk-based. `main` is protected (PR only, squash only, no force push). Branches: `propose/<change-id>` and `feat/<change-id>-<NN>` |
| Claude in CI     | `anthropics/claude-code-action@v1`, authenticated with the `CLAUDE_CODE_OAUTH_TOKEN` repository secret                              |
| Repository       | Public. Workflows that hold secrets never run for pull requests from forks                                                          |

### 0.2 Principles

1. **Claude does the work and explains it. Deterministic machines and Cristian
   close the gates.** No merge depends on a model's opinion alone.
2. **Three things are never left to the model's goodwill**: finishing with red
   tests, destroying infrastructure or data, and merging without Cristian's
   explicit approval. Each is enforced by a hook, a permission rule or GitHub.
3. **Minimal harness.** No roles, no launchers, no custom subagents, no
   path-scoped rules. A rule is added only after Claude makes the same mistake
   twice. Modern models know Go, React and Terraform conventions.
4. **State lives in files, not in the conversation.** Every session can start
   from zero: the change, its slices and their reports are in the repository.
5. **If a script can decide pass/fail, a script decides.** Claude is used only
   where judgment is needed.

### 0.3 The workflow the harness implements

```
/propose  (plan mode)  → interview → change folder → PR propose/<id> → Cristian approves → merge
/build <id> <NN>  (plan mode, one slice per session)
                       → plan → Cristian approves → tests first → code → make check/test/e2e
                       → slice report → PR feat/<id>-<NN>
CI on the PR           → deterministic jobs → /audit (Claude, read-only) comments a verdict
/ship <pr>             → waits for checks + verdict → short summary → asks Cristian → squash merge
CD (later change)      → no Claude; terraform apply needs Cristian's approval in GitHub
```

The last slice of a change also **archives** it (section 3.4.2): its delta specs
are merged into `openspec/specs/` inside that slice's PR, so the audit sees the
spec update together with the code.

## 1. Scope of this change

**In scope** — create exactly these files:

```
CLAUDE.md
Makefile
README.md                                   (replace the one-line placeholder)
.gitignore
.claude/settings.json
.claude/hooks/guard.sh
.claude/hooks/guard_test.sh
.claude/hooks/format.sh
.claude/hooks/stop-tests.sh
.claude/skills/propose/SKILL.md
.claude/skills/build/SKILL.md
.claude/skills/audit/SKILL.md
.claude/skills/ship/SKILL.md
.claude/templates/proposal.md
.claude/templates/design.md
.claude/templates/tasks.md
.claude/templates/spec-delta.md
.claude/templates/slice-report.md
.claude/templates/audit-comment.md
.claude/templates/ship-summary.md
openspec/specs/.gitkeep
openspec/changes/.gitkeep
openspec/changes/archive/.gitkeep
tools/spec-lint/                            (Go module: main.go, tests, testdata/)
tools/change-guard.sh
tools/change-guard_test.sh
tools/plan-guard.sh
tools/plan-guard_test.sh                    (+ JSON fixtures)
.github/workflows/ci.yml
.github/pull_request_template.md
docs/harness-spec.md                        (this file, already present)
```

**Out of scope** — do not create: `api/`, `web/`, `e2e/`, `infra/`,
`docker-compose.yml`, `.github/workflows/cd.yml`, `.github/workflows/verify.yml`,
any migration skill, any custom subagent, any `.claude/rules/` file. Do not
change GitHub or AWS settings.

## 2. Repository conventions

- **Change ids** are kebab-case nouns: `bootstrap`, `users-crud`.
- **Slices** are numbered `01`, `02`… inside a change.
- **Branches**: `propose/<id>` for a change proposal, `feat/<id>-<NN>` for a slice.
- **Commits**: Conventional Commits (`feat:`, `fix:`, `test:`, `docs:`, `chore:`,
  `ci:`, `refactor:`). PRs are squash-merged; the PR title is the final commit
  message and follows the same convention.
- **Approved change files** — `proposal.md`, `design.md`, `tasks.md` and
  `specs/**` inside `openspec/changes/<id>/` — are immutable once merged to
  `main`. Only the change's `reports/` folder grows, and archiving moves the
  folder whole. A design change is a new change.

## 3. File by file

### 3.1 `CLAUDE.md`

Short — **at most 90 lines**. It is loaded in every session, so every line must
be something Claude would get wrong without it. Sections, in this order:

1. **Project** — one paragraph: what it is, the stack, the folders (`api/`,
   `web/`, `e2e/`, `infra/`, `openspec/`, `tools/`), and that some do not exist
   yet.
2. **How we work** — the workflow of 0.3 in a few lines; the four skills and
   when to use each; one slice per session; work always starts in plan mode.
3. **Commands** — the Makefile verbs (3.2) and what each runs. Never call the
   underlying tools directly when a verb exists.
4. **Specs** — where they live (`openspec/specs/` = what the system does today;
   `openspec/changes/<id>/` = a change in flight); the immutability rule of
   section 2; if code and spec disagree, stop and say so.
5. **Git** — never commit or push on `main`; branch names; Conventional Commits;
   never force push; never merge except through `/ship`.
6. **Testing** — tests first; a red run is recorded before the implementation;
   existing test files merged to `main` are not weakened or deleted.
7. **Safety** — never run `terraform apply` or `terraform destroy` locally;
   never wipe Docker volumes; a hook block is final: adapt or report, never
   look for another way to do the same thing.
8. **Compaction** — "When compacting, preserve: the change id and slice in
   progress, the list of modified files, the commands that verify the slice,
   and any open decision."

No language style guides. No file-by-file descriptions of the codebase.

### 3.2 `Makefile`

The only interface the harness, CI and Cristian use. Verbs:

| Target         | Behaviour now (no app yet)                                                                                                            | Behaviour once the folder exists                                                                                                                                              |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `check`        | Runs `make harness-test`; prints `skip: api/` / `skip: web/` / `skip: infra/` for absent folders                                      | `gofmt -l` (fails on output) + `go vet ./...` in `api/`; `npm run lint` + `npm run typecheck` in `web/`; `terraform fmt -check -recursive` + `terraform validate` in `infra/` |
| `test`         | Prints skips, exits 0                                                                                                                 | `go test -race -count=1 ./...` in `api/`; `npm test -- --run` in `web/`                                                                                                       |
| `e2e`          | Prints skip, exits 0                                                                                                                  | Playwright in `e2e/` against the local stack                                                                                                                                  |
| `up` / `down`  | Prints skip, exits 0                                                                                                                  | `docker compose up -d --wait` / `docker compose down` (never `-v`)                                                                                                            |
| `harness-test` | Runs `.claude/hooks/guard_test.sh`, `tools/change-guard_test.sh`, `tools/plan-guard_test.sh` and `go test ./...` in `tools/spec-lint` | same                                                                                                                                                                          |
| `spec-lint`    | `go run ./tools/spec-lint openspec`                                                                                                   | same                                                                                                                                                                          |

Rules: every target exits 0 on today's repository; a target fails loudly
(non-zero) on a real failure; skips are printed, never silent. Add a `help`
target as the default.

### 3.3 `.claude/settings.json`

```jsonc
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "permissions": {
    "defaultMode": "plan",
    "allow": [
      /* see below */
    ],
    "ask": [
      /* see below */
    ],
    "deny": [
      /* see below */
    ],
  },
  "effortLevel": "high",
  "showClearContextOnPlanAccept": true,
  "enabledPlugins": {
    "gopls-lsp@claude-plugins-official": true,
    "typescript-lsp@claude-plugins-official": true,
  },
  "sandbox": { "enabled": true },
  "hooks": {
    /* section 3.5 */
  },
}
```

- **allow** — `make *`, `go test *`, `go vet *`, `go build *`, `go mod *`,
  `go run ./tools/*`, `npm run *`, `npm ci`, `npx playwright *`,
  `terraform fmt *`, `terraform validate*`, `terraform init *`,
  `terraform plan *`, `git status*`, `git diff*`, `git log*`, `git branch*`,
  `git switch *`, `git add *`, `git commit *`, `git pull*`, `git fetch*`,
  `git mv *`, `git push -u origin feat/*`, `git push -u origin propose/*`,
  `git push origin feat/*`, `git push origin propose/*`, `gh pr create *`,
  `gh pr view *`, `gh pr diff *`, `gh pr checks *`, `gh pr list *`,
  `gh issue list *`.
- **ask** (Claude Code always prompts, even in auto mode) — `Bash(gh pr merge *)`;
  `Edit` and `Write` on `.claude/**`, `.github/workflows/**`, `CLAUDE.md`
  and `Makefile`. These prompts are Cristian's approvals.
- **deny** — `Bash(git push --force*)`, `Bash(git push -f*)`,
  `Bash(git push origin main*)`, `Bash(git push * main)`,
  `Bash(terraform apply*)`, `Bash(terraform destroy*)`,
  `Bash(docker volume rm*)`, `Bash(docker volume prune*)`,
  `Bash(git reset --hard*)`.

Verify every rule against the permission syntax in
<https://code.claude.com/docs/en/permissions> before writing it; a mistyped
rule silently allows what it meant to forbid. The guard (3.5.1) is the floor
under these rules, not a replacement.

**Sandbox.** Enable it. Nothing in this change needs to escape it. If a later
change finds a command that cannot work inside it (Docker is the likely one),
that change adds the narrowest `sandbox.excludedCommands` entry and says so in
its report — never `sandbox.enabled: false`.

**Plugins.** The plugins need `gopls` and `typescript-language-server` on the
`PATH` (already installed on Cristian's machine). If the session cannot enable
them, report it; do not install binaries.

### 3.4 Skills

Every skill has frontmatter with `name`, `description`, `model`, `effort`,
`argument-hint` where it takes arguments, and `disable-model-invocation: true`
(they have side effects and are run by name). Each skill reads only what it
needs, writes its outputs from the templates in `.claude/templates/`, and ends
with a short message saying what happened and what comes next.

| Skill      | model    | effort   | Runs                           |
| ---------- | -------- | -------- | ------------------------------ |
| `/propose` | `opus`   | `xhigh`  | Locally, on `main`             |
| `/build`   | `opus`   | `high`   | Locally, one slice per session |
| `/audit`   | `opus`   | `high`   | In CI only                     |
| `/ship`    | `sonnet` | `medium` | Locally                        |

Confirm the frontmatter keys against <https://code.claude.com/docs/en/skills>.

#### 3.4.1 `/propose <change-id> [one-line idea]`

1. Preconditions: on `main`, clean tree, up to date with `origin/main`;
   `openspec/changes/<id>/` does not exist. Otherwise stop and say why.
2. Read `openspec/specs/` and, if code exists, map it with the built-in
   `Explore` subagent.
3. Interview Cristian with `AskUserQuestion`: one open decision at a time, a
   concrete proposal with its reason instead of an open question, two or three
   real options where there is a genuine choice. Argue; do not transcribe.
   Spend the time on what is expensive to change (data model, invariants, error
   semantics, infrastructure); propose and move on for the rest.
4. Write `openspec/changes/<id>/` from the templates:
   - `proposal.md` — why, what changes, what is explicitly out of scope.
   - `design.md` — how: decisions with their reasons, rejected alternatives.
   - `specs/<capability>/spec.md` — delta specs (3.6) with `## ADDED`,
     `## MODIFIED` and `## REMOVED Requirements`; every requirement has at
     least one scenario.
   - `tasks.md` — the change split into **slices**. A slice is one coherent,
     independently mergeable unit (an endpoint with its tests, a schema
     change, a deployment step) of at most about a day of work. Each slice has:
     goal, scope, out of scope, and an **acceptance criteria table** where
     every criterion names the test or the command that verifies it. "Works
     well" is not a criterion.
5. Run `make spec-lint`; fix until it passes.
6. Branch `propose/<id>`, commit `docs(<id>): propose <id>`, push, open the PR
   with the template, and tell Cristian the PR number and that `/ship <pr>`
   merges it once he has read it.

#### 3.4.2 `/build <change-id> <NN>`

**New slice**

1. Preconditions: on `main`, clean, up to date; `openspec/changes/<id>/` exists
   on `main`; slice `NN` exists in `tasks.md` and has no report yet; every
   earlier slice has a report. Otherwise stop and say why.
2. Read the slice in `tasks.md`, `proposal.md`, `design.md`, the change's delta
   specs and the previous slice report. Present the plan (plan mode); wait for
   approval.
3. Branch `feat/<id>-<NN>`.
4. **Red.** Write the tests named in the acceptance criteria first, with
   compiling stubs, and run them. They must fail on assertions, not on
   compilation. Keep the output for the report.
5. **Green.** Implement the minimum inside the slice's scope. Never widen the
   scope to make a test pass; if a criterion cannot be met within scope, stop
   and say so in the report.
6. **Verify.** `make check`, `make test`, and `make e2e` when the slice touches
   the UI or the API. Everything green. Keep every command and its result.
7. **Archive, last slice only.** If `NN` is the change's last slice: merge the
   delta specs into `openspec/specs/<capability>/spec.md` (ADDED appended,
   MODIFIED replacing the requirement with the same name, REMOVED deleted),
   then `git mv openspec/changes/<id> openspec/changes/archive/<YYYY-MM-DD>-<id>`.
   Run `make spec-lint`.
8. **Report.** Write `reports/slice-<NN>.md` (inside the change folder, or the
   archived folder) from the template: what changed and why (linked to
   requirement names), how it works (a small diagram when it helps), how it was
   tested (red and green evidence), **decisions made on Cristian's behalf**,
   risks and debt, and three commands Cristian can run to check it himself.
9. Commit (Conventional Commits, small logical commits are fine), push, open
   the PR with the template; title `feat(<id>): <slice goal>`.
10. Tell Cristian the PR number, that CI and the audit are running, that
    `/ship <pr>` comes next, and to **start a new session** for the next slice.

**Fix round** — when the PR's latest audit comment says `CHANGES REQUESTED`:

1. If the report already has a `## Fix round` section, stop: the slice has had
   its one fix round and Cristian decides.
2. Address every **blocking** finding; fix non-blocking ones only if trivial and
   inside scope. Existing tests stay as they are.
3. Re-run step 6, append `## Fix round` to the report (finding → change →
   evidence), commit `fix(<id>): address audit round 1`, push.

#### 3.4.3 `/audit <pr-number>` (CI only)

Read-only. It never edits code, never commits, never fixes anything.

1. Read: the PR diff, the PR description, the change folder the PR belongs to
   (`openspec/changes/<id>/` or its archived copy), `CLAUDE.md`, the CI job
   results (`gh pr checks`) and, when present, the `terraform plan` output the
   CI job published.
2. **Round** = number of previous audit comments on the PR + 1. Round 1 is the
   full audit. Round 2 only checks that every blocking finding of round 1 is
   resolved and that the fix broke nothing; anything new it sees is
   non-blocking. There is no round 3: a third request posts
   `Halted: Cristian decides.` and stops.
3. Check: every acceptance criterion of the slice has a test or command that
   asserts exactly it (a test that exists but does not assert it does not
   count); the code does what the change's requirements and scenarios say;
   nothing outside the slice's scope was changed; no rule of `CLAUDE.md` is
   broken; no secret, credential or personal data is committed; tests were not
   weakened.
4. **Classify.** A finding is **blocking** only if it breaks an acceptance
   criterion, a requirement or scenario of the change, or a rule of
   `CLAUDE.md` — and it names which. Everything else is **non-blocking**,
   however serious it sounds. A contradiction between two parts of the change
   is not a finding: name both and halt.
5. **Publish** one PR comment from `audit-comment.md`: the verdict
   (`APPROVED` or `CHANGES REQUESTED`), the findings table (severity, location
   `path:line`, finding, what it breaks), and — when a plan exists — the
   Terraform plan explained in plain words, calling out anything that replaces
   or deletes a resource.
6. For each non-blocking finding that calls for a code change, open a GitHub
   issue labelled `debt` (create the label if missing), unless an open `debt`
   issue already describes the same problem.

#### 3.4.4 `/ship <pr-number>`

1. Wait for the PR's checks: `gh pr checks <pr> --watch`. Any red check →
   stop and report it.
2. Read the latest audit comment. Not `APPROVED` → stop: for a slice PR, the
   next step is `/build <id> <NN>` (fix round); for a halted PR, Cristian
   decides. A `propose/*` PR needs no audit verdict, only green checks.
3. Write the **ship summary** from `ship-summary.md`: at most ~15 lines — what
   was done (linked to requirements), how it was verified (tests and their
   counts, e2e, plan), the audit verdict and round, the debt issues opened, the
   decisions made on Cristian's behalf. It must be readable without opening
   the PR.
4. Ask: "Merge PR #<n> into main?" Then run
   `gh pr merge <pr> --squash --delete-branch`. The `ask` rule makes Claude
   Code prompt Cristian for this command: that prompt is his green light. Never
   look for another way to merge.
5. `git switch main && git pull`. Report what comes next (the next slice, or
   that the change is complete).

### 3.5 Hooks

All hooks: `bash`, `set -uo pipefail`, read the hook payload from stdin with
`jq`, exit `0` to allow and `2` to block (stderr goes to Claude). Regexes must
work with both GNU and BSD (macOS) `grep`. Wire them in `settings.json` with
`"$CLAUDE_PROJECT_DIR"/.claude/hooks/<name>.sh`.

| Event         | Matcher                           | Script          |
| ------------- | --------------------------------- | --------------- |
| `PreToolUse`  | `Bash\|Edit\|Write\|NotebookEdit` | `guard.sh`      |
| `PostToolUse` | `Edit\|Write`                     | `format.sh`     |
| `Stop`        | —                                 | `stop-tests.sh` |

#### 3.5.1 `guard.sh`

Blocks, whatever the permission rules say. Each simple command of a Bash line
(split on `;`, `&`, `|`) is checked on its own.

| #   | Blocks                                                                                                                                                                                                  | Allows (must not be blocked)                                                                                                         |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| G1  | `docker compose … down … -v` / `--volumes`, `docker volume rm`, `docker volume prune`                                                                                                                   | `docker compose down`                                                                                                                |
| G2  | `terraform apply`, `terraform destroy` (any flags)                                                                                                                                                      | `terraform plan`, `terraform fmt`                                                                                                    |
| G3  | `git commit` while the current branch is `main`                                                                                                                                                         | `git commit` on `feat/*` or `propose/*`                                                                                              |
| G4  | `git push` that targets `main`, and any `--force` / `-f` / `--force-with-lease` push                                                                                                                    | `git push -u origin feat/x-01`                                                                                                       |
| G5  | On a `feat/*` branch: writes (Edit/Write/NotebookEdit, or shell `rm`, `mv`, `cp`, `tee`, `>`, `>>`, `sed -i`, `truncate`) to `openspec/changes/<id>/proposal.md`, `design.md`, `tasks.md` or `specs/**` | Writes to `openspec/changes/<id>/reports/**`; `git mv openspec/changes/<id> openspec/changes/archive/<date>-<id>` (the whole folder) |
| G6  | Writes to a file under `api/migrations/` that already exists on `main`                                                                                                                                  | Creating a new migration file                                                                                                        |
| G7  | Any non-Bash tool whose payload has neither `file_path` nor `notebook_path` (fail closed), and every call when `jq` is missing                                                                          | —                                                                                                                                    |

Paths are compared relative to `$CLAUDE_PROJECT_DIR`. The block message says
what was blocked, why, and the allowed way to do it.

**`guard_test.sh`** builds a throwaway git repository under `$TMPDIR` (with
`main`, a `feat/demo-01` branch, an `openspec/changes/demo/` folder and a
committed `api/migrations/000001_init.up.sql`), pipes one payload per case into
`guard.sh` and asserts the exit code. **At least one blocked case and one
allowed case per row of the table.** It prints `PASS`/`FAIL` per case and exits
non-zero if any case fails. It never touches the real repository.

#### 3.5.2 `format.sh`

After an Edit or Write, format the file by extension, only if it exists and
the tool is available; a missing tool is a silent skip (exit 0):

- `.go` → `gofmt -w`; then `go vet` on its package if `api/go.mod` exists.
- `.ts`, `.tsx`, `.js`, `.jsx`, `.css`, `.json` under `web/` or `e2e/` →
  the project's local Prettier (`node_modules/.bin/prettier --write`) if present.
- `.tf` → `terraform fmt`.

A formatter or `go vet` failure exits 2 with the last 30 lines of output.

#### 3.5.3 `stop-tests.sh`

Only on `feat/*` branches (exit 0 elsewhere). If the payload's
`stop_hook_active` is `true`, exit 0 (no endless loop). Otherwise run
`make test`; on failure exit 2 with the last 30 lines and the message
"`make test` is failing. Fix it before finishing, or stop and explain why in
the report."

### 3.6 Spec format (OpenSpec-compatible)

`openspec/specs/<capability>/spec.md` — what the system does today:

```markdown
# <Capability> specification

## Purpose

<One paragraph.>

## Requirements

### Requirement: Create a user

The system SHALL create a user with a unique email.

#### Scenario: Duplicate email

- **WHEN** a user is created with an email that already exists
- **THEN** the API responds 409 with code `email_taken`
- **AND** no user is created
```

`openspec/changes/<id>/specs/<capability>/spec.md` — a delta: the same
requirement blocks under `## ADDED Requirements`, `## MODIFIED Requirements`
(the full new text of a requirement with the same name) and
`## REMOVED Requirements` (the name and a `**Reason**:` line).

Requirements use RFC 2119 keywords (SHALL, MUST, SHOULD). Requirement names
are unique within a capability; they are the IDs that slices, tests and
reports cite.

### 3.7 `tools/spec-lint` (Go module)

`go run ./tools/spec-lint <dir>` walks `openspec/` and exits non-zero listing
**every** violation as `path:line: rule: message`:

| Rule | Checks                                                                                                                                                                         |
| ---- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| L1   | Each folder in `openspec/changes/` (except `archive/`) has `proposal.md`, `design.md`, `tasks.md` and at least one `specs/<capability>/spec.md`                                |
| L2   | A delta spec has at least one of the three `## … Requirements` sections and no other `##` section                                                                              |
| L3   | Every `### Requirement: <name>` has a non-empty body with SHALL or MUST and at least one `#### Scenario:`                                                                      |
| L4   | Every scenario has at least one `WHEN` and one `THEN` line                                                                                                                     |
| L5   | Requirement names are unique within a file                                                                                                                                     |
| L6   | `tasks.md` has at least one `## Slice NN — <title>` section, numbered from 01 without gaps, each with an acceptance criteria table whose `Verified by` cells are all non-empty |
| L7   | `openspec/specs/<capability>/spec.md` has `## Purpose` and `## Requirements` and obeys L3–L5                                                                                   |
| L8   | No `<placeholder>` left anywhere                                                                                                                                               |

Standard library only. Table-driven tests with fixtures in `testdata/`: one
valid tree that passes, and one failing fixture per rule that fails with that
rule's id.

### 3.8 `tools/change-guard.sh`

The CI twin of G5, outside the agent's reach. Given a base ref, it reads
`git diff --name-status --find-renames <base>...HEAD` and fails if a PR whose
head branch is `feat/*` **modifies or deletes** an approved change file
(section 2). Pure renames (`R100`) of a whole change folder into
`openspec/changes/archive/` and any change under `reports/` are allowed.
`propose/*` branches are not checked. `change-guard_test.sh` covers: a
modification (fails), a report added (passes), an archive move (passes), a
`propose/*` branch (passes).

### 3.9 `tools/plan-guard.sh`

Reads the JSON of a plan (`terraform show -json <planfile>`) and fails, listing
the addresses, if any `resource_changes[].change.actions` contains `"delete"`
(this includes replacements). Exit 0 otherwise. `plan-guard_test.sh` runs it
against three fixtures: create-only (passes), update in place (passes),
replace (fails).

### 3.10 `.github/workflows/ci.yml`

- **Triggers**: `pull_request` to `main` (`opened`, `synchronize`, `reopened`,
  `ready_for_review`) and `workflow_dispatch`.
- **Top-level permissions**: `contents: read`. Each job widens only what it
  needs.
- **Concurrency**: one run per PR, cancel in progress.
- Pin actions to a major version at least. Use `actions/setup-go` and
  `actions/setup-node`.

Jobs — **these names are stable**: Cristian marks them as required checks
after this PR merges.

| Job         | Runs                                                                                                                                               | Notes                                                                                                |
| ----------- | -------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| `harness`   | `make harness-test`                                                                                                                                |                                                                                                      |
| `spec`      | `make spec-lint` and `tools/change-guard.sh origin/main`                                                                                           | `fetch-depth: 0`                                                                                     |
| `checks`    | `make check` and `make test`                                                                                                                       | Skips print, pass                                                                                    |
| `e2e`       | `make e2e`                                                                                                                                         | Skips print, pass                                                                                    |
| `terraform` | Skips while `infra/envs/` does not exist; later: `fmt`, `validate`, `plan`, `plan-guard`, and publishes the plan text as an artifact for the audit | AWS OIDC wiring comes with the bootstrap change; leave a clear `TODO(bootstrap)` comment, no secrets |
| `audit`     | `anthropics/claude-code-action@v1` with `prompt: "/audit ${{ github.event.pull_request.number }}"`                                                 | See below                                                                                            |

**`audit` job**:

- `needs` every other job; runs only if they all succeeded.
- Runs only when the PR is not a draft, its head branch starts with `feat/`,
  and the head repository is this repository (never for forks).
- Permissions: `contents: read`, `pull-requests: write`, `issues: write`,
  `id-token: write`, `actions: read`.
- Inputs: `claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}`;
  `claude_args` with `--model opus`, a `--max-turns` cap and an
  `--allowedTools` list limited to reading files and the `gh` commands the
  skill needs (`gh pr view`, `gh pr diff`, `gh pr checks`, `gh pr comment`,
  `gh issue list`, `gh issue create`, `gh label create`).
- Job `timeout-minutes: 20`.
- Check every input name against
  <https://code.claude.com/docs/en/github-actions> before writing it.

The audit job's outcome is not a gate: it passes even when the verdict is
`CHANGES REQUESTED`. The gate is `/ship`, which refuses to merge without
`APPROVED`.

### 3.11 Templates

`.claude/templates/`: `proposal.md`, `design.md`, `tasks.md` (with one example
slice and its acceptance criteria table), `spec-delta.md`, `slice-report.md`,
`audit-comment.md`, `ship-summary.md`. Each has the exact headings the skills
write and short `<placeholder>` hints. `.github/pull_request_template.md`:
summary, change and slice, how it was verified, link to the slice report,
checklist (tests first, `make check`/`test`/`e2e` green, no secrets).

### 3.12 `README.md` and `.gitignore`

`README.md`: what the project is, the stack, and a short "How this repository
is built" section describing the workflow of 0.3 in plain words, for readers
who are not Claude. No badges, no marketing.

`.gitignore`: Go (`*.test`, `cover.out`, binaries), Node (`node_modules/`,
`dist/`, `playwright-report/`, `test-results/`), Terraform (`.terraform/`,
`*.tfstate*`, `*.tfplan`, `crash.log`), environment files (`.env`, `.env.*`
except `.env.example`), macOS (`.DS_Store`), Claude Code personal files
(`.claude/settings.local.json`, `CLAUDE.local.md`).

## 4. Acceptance criteria

| ID  | Criterion                                                                                                     | Verified by                                     |
| --- | ------------------------------------------------------------------------------------------------------------- | ----------------------------------------------- |
| H01 | Every file of section 1 exists; nothing out of scope was created                                              | `git diff --name-status main...HEAD`            |
| H02 | `make check`, `make test`, `make e2e`, `make up`, `make down` exit 0 on this repository and print their skips | Run each                                        |
| H03 | `make harness-test` passes                                                                                    | Run it                                          |
| H04 | `guard_test.sh` has a blocked and an allowed case for every row G1–G7, and all pass                           | Read the script; run it                         |
| H05 | `spec-lint` passes on a valid tree and fails each invalid fixture with its rule id                            | `go test ./...` in `tools/spec-lint`            |
| H06 | `change-guard.sh` and `plan-guard.sh` behave as in 3.8 and 3.9                                                | Their test scripts                              |
| H07 | `.claude/settings.json` is valid JSON and every key and rule exists in the current Claude Code docs           | `jq . .claude/settings.json`; docs links in 3.3 |
| H08 | Every skill has the frontmatter of 3.4 and follows its steps                                                  | Read them                                       |
| H09 | `CLAUDE.md` is at most 90 lines and has the sections of 3.1                                                   | `wc -l CLAUDE.md`                               |
| H10 | On this PR, jobs `harness`, `spec`, `checks`, `e2e` and `terraform` are green                                 | GitHub checks                                   |
| H11 | A new session in this repo starts in plan mode                                                                | Cristian, manually                              |
| H12 | Asking Claude to run `git push --force` or `terraform destroy` is refused                                     | Cristian, manually                              |
| H13 | Merging this PR with `gh pr merge` from a session triggers the permission prompt                              | Cristian, when merging                          |

H11–H13 are Cristian's probes. Note in the PR description that they are
pending.

**The audit on this PR.** The `audit` job only runs on `feat/*` branches, so it
runs here — but `/audit` expects an OpenSpec change, and this PR has none. For
this PR only, the audit uses **this document** as the change: its section 4 is
the acceptance criteria and its section 1 is the scope. Write that exception
into the `/audit` skill as a single line that names this file and is removed
together with it.

## 5. How to implement

1. Work on `feat/harness-skeleton`, already created, with this file at
   `docs/harness-spec.md`.
2. Before writing settings, hooks, skills or the workflow, check the current
   documentation for each (links above). Where this spec and the docs
   disagree, **follow the docs and say so in the PR description.**
3. Commit in logical steps: hooks + tests; tools + tests; skills + templates;
   settings + CLAUDE.md + Makefile; workflow; README and `.gitignore`.
4. Run `make harness-test` and the verbs of H02 before opening the PR.
5. Open the PR with `gh pr create`; title
   `chore(harness): skeleton of the Claude Code harness`. The description
   lists: what was built, every decision made where this spec was silent, every
   point where the docs overrode this spec, and the pending manual probes
   H11–H13.
6. Do not merge.

## 6. After the merge (Cristian)

1. Settings → Rules → `main-protection` → add "Require status checks to pass"
   with `harness`, `spec`, `checks`, `e2e` and `terraform`.
2. Delete `docs/harness-spec.md` and the one-line exception in `/audit` in the
   first commit of the `bootstrap` change.
