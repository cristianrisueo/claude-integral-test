---
name: audit
description: CI only. Read-only audit of a feat/* PR against its OpenSpec change. Posts one verdict comment (APPROVED or CHANGES REQUESTED) and opens debt issues. Never edits, commits or fixes anything.
argument-hint: <pr-number>
model: opus
effort: high
disable-model-invocation: true
---

# /audit $0

You audit PR #$0. You are **read-only**: never edit a file, commit, push or fix anything. Your only outputs are one PR comment and, for non-blocking debt, GitHub issues. You can use these tools:

- the file tools (Read, Glob, Grep);
- `gh pr view`, `gh pr diff`, `gh pr checks`, `gh pr comment`;
- `gh issue list`, `gh issue create`, `gh label create`.

## 1. Read

1. `gh pr view $0 --json number,title,body,headRefName,isDraft,comments`
2. The change id and slice come from the head branch `feat/<change-id>-<NN>`.
3. Read the change folder, `openspec/changes/<change-id>/` or its archived copy `openspec/changes/archive/*-<change-id>/`:
   - slice `<NN>` in `tasks.md`;
   - `proposal.md`;
   - the delta specs;
   - `reports/slice-<NN>.md`.
4. `gh pr diff $0`, `CLAUDE.md`, and the CI results with `gh pr checks $0`.
5. If the CI `terraform` job published a plan, read it too.

## 2. Round

Count the PR's previous comments that start with `<!-- harness:audit -->`. Round = that count + 1.

- **Round 1** is the full audit.
- **Round 2** only checks two things: every blocking finding of round 1 is resolved, and the fix broke nothing. Anything new you see in round 2 is non-blocking.
- **Round 3 or later:** post a comment with the `<!-- harness:audit -->` marker, the heading `## Audit: HALTED` and the line `Halted: Cristian decides.`, then stop.

## 3. Check

- Every acceptance criterion of the slice has a test or command that asserts **exactly** it. A test that exists but does not assert the criterion does not count.
- The code does what the change's requirements and scenarios say.
- Nothing outside the slice's scope (its Scope and Out of scope) was changed.
- No rule of `CLAUDE.md` is broken.
- No secret, credential or personal data is committed.
- Tests were not weakened: no deleted or loosened assertions, and no skipped tests in files that exist on `main`.

## 4. Classify

A finding is **blocking** only if it breaks an acceptance criterion, a requirement or scenario of the change, or a rule of `CLAUDE.md`, and it names which one. Everything else is **non-blocking**, however serious it sounds.

A contradiction between two parts of the change is not a finding. Post a comment with the `<!-- harness:audit -->` marker and the heading `## Audit: HALTED` that names both parts and ends with `Halted: Cristian decides.`, then stop.

## 5. Publish

Open the debt issues of step 6 first, so the comment can list them. Then post exactly one comment, filled from `.claude/templates/audit-comment.md`, with:

```
gh pr comment $0 --body-file - <<'EOF'
…
EOF
```

- The first line stays `<!-- harness:audit -->`.
- The verdict is `APPROVED` when there are no blocking findings, and `CHANGES REQUESTED` otherwise.
- The findings table gives severity, `path:line`, the finding, and what it breaks.
- When a Terraform plan exists, explain it in plain words and call out anything that replaces or deletes a resource.

## 6. Debt issues

For each non-blocking finding that calls for a code change:

1. `gh label create debt --color D93F0B --description "Non-blocking audit finding" --force`. It is idempotent.
2. Look for an open issue that already describes the same problem: `gh issue list --label debt --state open --search "<keywords>"`.
3. If none exists, `gh issue create --label debt --title "<short title>" --body "<finding, location, PR #$0>"`.

List these issues in the comment's "Debt issues" section.

## 7. Finish

End with one line: the verdict, the round, and the number of blocking findings and of debt issues.
