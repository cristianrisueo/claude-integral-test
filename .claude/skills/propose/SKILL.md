---
name: propose
description: Propose a new change. Interview Cristian, write openspec/changes/<change-id>/ (proposal, design, delta specs, tasks split into slices), lint it and open the propose/<change-id> PR. Run on main, in plan mode.
argument-hint: <change-id> [one-line idea]
model: opus
effort: xhigh
disable-model-invocation: true
---

# /propose $0

Change id: `$0`. Full arguments: `$ARGUMENTS` (everything after the id is the idea, possibly empty).

You turn an idea into an approved, sliced change. The change folder is the contract every later session builds from, so be precise. Work in plan mode until the interview is done.

## 1. Preconditions

Check all of these; if any fails, stop and say which and why:

- `$0` is a kebab-case noun (`^[a-z][a-z0-9]*(-[a-z0-9]+)*$`), e.g. `users-crud`.
- `git branch --show-current` is `main` and `git status --porcelain` prints nothing.
- After `git fetch origin main`, `git rev-parse HEAD` equals `git rev-parse origin/main`.
- `openspec/changes/$0/` does not exist, and no `openspec/changes/archive/*-$0/` exists.

## 2. Read

- Read `openspec/specs/` (what the system does today).
- If application code exists (`api/`, `web/`, `e2e/`, `infra/`), map the parts this idea touches with the built-in `Explore` subagent. Do not read the whole codebase yourself.

## 3. Interview Cristian

Use `AskUserQuestion`, one open decision at a time.

- Bring a concrete proposal and its reason, not an open question. Offer two or three real options only where there is a genuine choice, recommended one first.
- Argue: if an answer creates a contradiction or a cost Cristian may not see, say so. Do not transcribe.
- Spend the questions on what is expensive to change later: data model, invariants, error semantics (status and error codes), infrastructure. For everything else, propose a default, state it, and move on.
- Stop when every requirement can be written with a SHALL/MUST and a WHEN/THEN scenario, and the work can be cut into slices.

Then present the plan with `ExitPlanMode`: the capabilities, the requirement names, and the slices with their goals. Write nothing before it is approved.

## 4. Write `openspec/changes/$0/` from the templates

Copy the headings of each template in `.claude/templates/` exactly and replace every `<placeholder>`:

- `proposal.md` from `proposal.md`: why, what changes, what is explicitly out of scope.
- `design.md` from `design.md`: how, with each decision, its reason and its rejected alternatives.
- `specs/<capability>/spec.md` from `spec-delta.md`, one per capability touched.
  - Keep only the `## ADDED`, `## MODIFIED` and `## REMOVED Requirements` sections that apply.
  - MODIFIED repeats the full new text of an existing requirement under its exact name.
  - REMOVED has the name and a `**Reason**:` line.
  - Every requirement uses SHALL or MUST and has at least one `#### Scenario:` with WHEN and THEN lines.
  - Requirement names are unique within a capability; they are the IDs slices, tests and reports cite.
- `tasks.md` from `tasks.md`.
  - Use one `## Slice NN — <title>` section per slice, numbered `01`, `02`… without gaps.
  - A slice is one coherent, independently mergeable unit of at most about a day of work: an endpoint with its tests, a schema change, a deployment step.
  - Each slice has a goal, its requirements, a scope, an out of scope, and an acceptance criteria table.
  - Every criterion in the table names the test or the exact command that verifies it. "Works well" is not a criterion.

## 5. Lint

Run `make spec-lint` and fix the change until it passes.

## 6. Open the PR

1. `git switch -c propose/$0`
2. `git add openspec/changes/$0` and commit `docs($0): propose $0`.
3. `git push -u origin propose/$0`
4. Open the PR with `gh pr create --title "docs($0): propose $0" --body-file -`. Fill the body from `.github/pull_request_template.md`; the slice is "proposal", and the slice report is not needed.

## 7. Finish

Tell Cristian, in a few lines:

- the PR number and the slices it defines;
- that a `propose/*` PR has no audit, only CI checks;
- that once he has read it, `/ship <pr>` merges it;
- that `/build $0 01` starts the first slice in a new session.
