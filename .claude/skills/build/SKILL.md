---
name: build
description: Build one slice of an approved change, tests first, and open its feat/<change-id>-<NN> PR; or run the slice's single fix round when its latest audit says CHANGES REQUESTED. One slice per session, starting in plan mode.
argument-hint: <change-id> <NN>
model: opus
effort: high
disable-model-invocation: true
---

# /build $0 $1

Change `$0`, slice `$1`. The branch is `feat/$0-$1`. Abbreviations below: `<id>` = `$0`, `<NN>` = `$1`, and `<change>` = `openspec/changes/$0/`.

## Which mode

Run `gh pr list --head feat/$0-$1 --state open --json number`.

- **No open PR:** this is a **new slice**; follow "New slice".
- **An open PR:** read its latest audit comment with `gh pr view <pr> --json comments`. Audit comments start with `<!-- harness:audit -->`.
  - `CHANGES REQUESTED`: follow "Fix round".
  - Anything else: stop and say what state the PR is in.

## New slice

### 1. Preconditions

Check all of these; if any fails, stop and say which and why:

- On `main`, `git status --porcelain` is empty, and after `git fetch origin main` HEAD equals `origin/main`.
- `<change>` exists on `main`.
- `## Slice $1 — …` exists in `<change>tasks.md`.
- `<change>reports/slice-$1.md` does not exist.
- Every earlier slice has its `reports/slice-<MM>.md`.

### 2. Read and plan

Read only:

- slice `$1` in `tasks.md`;
- `proposal.md`;
- the change's delta specs under `<change>specs/`;
- the previous slice report, if any.

Present the plan with `ExitPlanMode`: the tests you will write for each acceptance criterion, the files you will touch, and how the slice stays inside its scope. Wait for approval.

### 3. Branch

`git switch -c feat/$0-$1`

### 4. Red

- Write the tests named in the acceptance criteria first, with compiling stubs for the code they call.
- Run them. They must **fail on assertions, not on compilation**. Fix the stubs until they do.
- Keep the command and the failing output for the PR description.

### 5. Green

- Implement the minimum that makes the tests pass, inside the slice's scope.
- Never widen the scope to make a test pass. If a criterion cannot be met within scope, stop and say so in the report.
- Existing test files merged to `main` are not weakened or deleted.

### 6. Verify

- Run `make check` and `make test`, plus `make e2e` when the slice touches the UI or the API.
- Everything must be green. Keep every command and its result for the PR description.

### 7. Archive (last slice only)

If `$1` is the last slice in `tasks.md`:

1. Merge each delta spec into `openspec/specs/<capability>/spec.md`:
   - ADDED requirements are appended under `## Requirements`.
   - MODIFIED requirements replace the requirement with the same name.
   - REMOVED requirements are deleted.
   - A new capability gets a new file with `# <Capability> specification`, `## Purpose` (one paragraph) and `## Requirements`.
2. `git mv openspec/changes/$0 openspec/changes/archive/$(date +%F)-$0`
3. Run `make spec-lint` and fix `openspec/specs/` until it passes.

The guard blocks any other write to the change's approved files (`proposal.md`, `tasks.md`, `specs/**`). That is final.

### 8. Report

Write `reports/slice-$1.md` from `.claude/templates/slice-report.md`. It goes inside `<change>`, or inside the archived folder after step 7. The report is the one document Cristian reads to approve the merge, so write it like the proposal: short sentences, no jargon the reader has to look up. It has three sections:

- **What was done:** plain words, ending with the **decisions made on Cristian's behalf**, or "None.".
- **How we checked it:** one table, Criterion | Test or command | Result, with a row per acceptance criterion.
- **Check it yourself:** three commands Cristian can run, and what each should show.

The red and green evidence does not go in the report; it goes in the PR description (step 9).

### 9. Commit, push, PR

- Commit with Conventional Commits; small logical commits are fine.
- `git push -u origin feat/$0-$1`.
- `gh pr create --head feat/$0-$1 --title "feat($0): <slice goal>" --body-file -`, with the body filled from `.github/pull_request_template.md`. Its "Tests: red, then green" section holds the red run from step 4 (command and failing output, trimmed) and the green commands from step 6 with their results.

### 10. Finish

Tell Cristian:

- the PR number;
- that CI and the audit are running;
- that `/ship <pr>` comes next;
- to **start a new session** for the next slice.

## Fix round

Run this on `feat/$0-$1`, after `git switch feat/$0-$1 && git pull origin feat/$0-$1`. Name the branch explicitly: the sandbox cannot write `.git/config`, so `git push -u` does not record an upstream.

1. If the slice report already has a `## Fix round` section, stop: the slice has had its one fix round, and Cristian decides.
2. Address every **blocking** finding of the latest audit comment. Fix non-blocking findings only if they are trivial and inside the slice's scope. Existing tests stay as they are.
3. Re-run step 6 (Verify).
4. Append `## Fix round` to the report: a table of finding → change → evidence.
5. Commit `fix($0): address audit round 1` and push. CI re-runs, and the audit runs round 2.
6. Tell Cristian that `/ship <pr>` comes next once round 2 is in.
