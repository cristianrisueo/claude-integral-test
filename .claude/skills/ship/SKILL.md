---
name: ship
description: Merge a PR into main. Waits for green checks and, for feat/* PRs, an APPROVED audit; writes a short ship summary; asks Cristian; then squash-merges.
argument-hint: <pr-number>
model: sonnet
effort: medium
disable-model-invocation: true
---

# /ship $0

You merge PR #$0, only when the gates are green and Cristian says yes. **Never look for another way to merge** than the command in step 4.

## 1. Checks

1. Run `gh pr view $0 --json number,title,headRefName,body,comments,state`. If the PR is not open, stop.
2. Run `gh pr checks $0 --watch`. If any check is red, stop and report which one and its link.

## 2. Audit verdict

- **`propose/*` PR:** it needs no audit verdict, only green checks. Go to step 3.
- **`feat/*` PR:** read the latest comment that starts with `<!-- harness:audit -->`.
  - `## Audit: APPROVED`: go on.
  - `## Audit: CHANGES REQUESTED`: stop. The next step is `/build <change-id> <NN>` (fix round), in a new session.
  - `## Audit: HALTED`, or no audit comment at all: stop. Cristian decides.
- **Any other branch:** stop and say so.

## 3. Ship summary

Write the summary from `.claude/templates/ship-summary.md`, at most about 15 lines. It must be readable without opening the PR. Include:

- what was done, linked to requirement names;
- how it was verified (tests and their counts, e2e, the Terraform plan);
- the audit verdict and round;
- the debt issues opened;
- the decisions made on Cristian's behalf.

The sources are the PR body, the slice report, the audit comment and the checks.

## 4. Merge

1. Show the summary, then ask with `AskUserQuestion`: "Merge PR #$0 into main?"
2. Only on a yes, run `gh pr merge $0 --squash --delete-branch`. Claude Code always prompts Cristian for this command, and that prompt is his green light. If he declines either question, stop.

## 5. Finish

1. Run `git switch main && git pull`.
2. Report what comes next:
   - **propose PR:** `/build <change-id> 01`, in a new session.
   - **Slice that is not the last:** `/build <change-id> <NN+1>`, in a new session.
   - **Last slice:** the change is complete; its folder is in `openspec/changes/archive/`.
