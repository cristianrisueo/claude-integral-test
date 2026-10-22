---
name: ship
description: Merge a PR into main. Waits for green checks and, for feat/* PRs, an APPROVED audit; shows the slice report, the proposal or, for chore/* PRs, the PR description; asks Cristian; then squash-merges.
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
- **`chore/*` PR:** harness maintenance. It needs no audit verdict, only green checks. Go to step 3.
- **`feat/*` PR:** read the latest comment that starts with `<!-- harness:audit -->`.
  - `## Audit: APPROVED`: go on.
  - `## Audit: CHANGES REQUESTED`: stop. The next step is `/build <change-id> <NN>` (fix round), in a new session.
  - `## Audit: HALTED`, or no audit comment at all: stop. Cristian decides.
- **Any other branch:** stop and say so.

## 3. Show the document

Do not write a summary. Show Cristian the one document he approves, followed by one line. For a `feat/*` or `propose/*` PR, take the document from `gh pr diff $0`: the PR adds it, so the diff holds all of it.

- **`feat/*` PR:** the slice report, `reports/slice-<NN>.md` in the change folder (or its archived copy), then `Audit: APPROVED (round N)`.
- **`propose/*` PR:** the change's `proposal.md`, then `No audit: propose PR, checks green`.
- **`chore/*` PR:** the PR description (the `body` from step 1), then `No audit: chore PR, checks green`.

## 4. Merge

1. Show the document, then ask with `AskUserQuestion`: "Merge PR #$0 into main?"
2. Only on a yes, run `gh pr merge $0 --squash --delete-branch`. Claude Code always prompts Cristian for this command, and that prompt is his green light. If he declines either question, stop.

## 5. Finish

1. Run `git switch main`, then `git pull`, as two separate commands.
   - If either fails with `unable to unlink old`, the sandbox stopped it from replacing a protected file under `.claude/skills/` or `.claude/hooks/`. Offer to rerun **that one command** unsandboxed, and wait for Cristian's approval. Retry nothing else.
   - Never add git commands to `sandbox.excludedCommands` to avoid this.
2. Run `git fetch --prune`.
3. Delete the local branch of the merged PR, the `headRefName` from step 1:
   - If `git branch --list <headRefName>` prints nothing, `gh pr merge --delete-branch` already deleted it. Skip this step.
   - Otherwise run `git branch -D <headRefName>`.
   - Never delete `main`.
4. Report what comes next:
   - **chore PR:** nothing; the harness change is live on `main`.
   - **propose PR:** `/build <change-id> 01`, in a new session.
   - **Slice that is not the last:** `/build <change-id> <NN+1>`, in a new session.
   - **Last slice:** the change is complete; its folder is in `openspec/changes/archive/`.
