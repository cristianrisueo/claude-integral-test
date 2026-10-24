---
name: retro
description: Read-only retrospective of an archived change. Measures how the harness behaved (audits, fix rounds, guard blocks, CI failures, prompts), proposes at most five improvements with evidence, writes docs/retros/<change-id>.md and opens its chore/retro-<change-id> PR. Never changes the harness.
argument-hint: <change-id>
model: opus
effort: high
disable-model-invocation: true
---

# /retro $0

You write the retrospective of change `$0`: how the harness behaved while it was built, and what to improve. You are **read-only**. The one file you write is `docs/retros/$0.md`. Never edit `.claude/`, `CLAUDE.md`, `Makefile`, `tools/`, `.github/`, `openspec/` or `src/`, and never apply a proposal, not even a small one. Cristian decides which proposals become a later `chore/*` PR.

Apart from the steps in "8. PR", run only commands that read.

## 1. Preconditions

Check all of these. If any fails, stop and say which and why:

- On `main`, `git status --porcelain` is empty, and after `git fetch origin main` HEAD equals `origin/main`.
- `openspec/changes/archive/*-$0/` exists and `openspec/changes/$0/` does not: the change is archived.
- `docs/retros/$0.md` does not exist.
- `gh pr list --head chore/retro-$0 --state open --json number` is empty.

## 2. The change

Read the archived folder: `proposal.md`, `tasks.md` (the number of slices), the delta specs, and every `reports/slice-*.md`. Note the decisions taken on Cristian's behalf, and any criterion that was hard to check.

## 3. GitHub

1. The change's PRs:
   `gh pr list --state all --limit 200 --json number,title,headRefName,createdAt,mergedAt --jq '.[] | select(.headRefName == "propose/$0" or (.headRefName | startswith("feat/$0-")))'`
2. For each PR, run `gh pr view <n> --json comments,commits,body`. Audit comments start with `<!-- harness:audit -->`. From them take the verdict of each round, which slices needed a fix round, and which were `HALTED`. A slice approved in round 1 is a first-pass approval.
3. Failed CI runs: `gh run list --branch <headRefName> --status failure --json databaseId,workflowName,createdAt` for each branch. For each run, find the cause with `gh run view <id> --log-failed | tail -n 40`, and sort it: harness, spec, change-guard, lint, unit tests, e2e, terraform, flaky, or CI setup.
4. Debt issues: `gh issue list --label debt --state all --search "PR #<n>" --json number,title,state` for each `feat/*` PR.
5. Time per slice, approximate: from `createdAt` to `mergedAt` of its PR.

## 4. Transcripts (best effort)

The SessionEnd hook copies every session to `.claude/sessions/<YYYY-MM-DD>-<session-id>.jsonl`. That folder is local and ignored by git, and the transcript format is internal to Claude Code and may change. The retro must work without them.

1. Find this change's sessions: `grep -l -e '/build $0' -e '/propose $0' -e 'feat/$0-' -e 'propose/$0' .claude/sessions/*.jsonl`. If there are none, every measure below is `unknown`; say so in the header line and go on.
2. Count with `grep -c` or `jq` over the files. Never read a whole transcript into the conversation.
   - Guard blocks: `BLOCKED by .claude/hooks/guard.sh [G<n>]`, counted per rule.
   - Stop-hook pushbacks: `` `make test` is failing ``.
   - Unsandboxed retries: tool calls with `"dangerouslyDisableSandbox":true`, and what each was for.
   - Declined permission prompts: tool results saying the user rejected or did not want the call. Report the count as approximate.
   - Session span: the first and last `timestamp` of each file.
   - Questions Claude asked (`AskUserQuestion`) whose answer was already in a file of the repository or the change.
3. If a marker is not found, or a file does not parse, report that measure as `unknown`, not as 0, and do not let it stop the retro.

## 5. Rules that never fired

List the rules with no trigger in this change:

- the guard rules G1 to G7;
- the Stop hook;
- the CI jobs harness, spec (spec-lint and change-guard), checks, e2e and terraform (plan-guard);
- the audit's blocking classes: acceptance criterion, requirement or scenario, `CLAUDE.md` rule.

Zero triggers is not bad by itself: a rule that blocks something rare still earns its place. Say which silent rules still look worth their cost, and which look like noise.

## 6. Proposals

At most five, `P1` to `P5`, ordered by value. Each one gives:

- the change;
- its evidence (PR, run id, report, rule or count);
- the expected effect: which number in "Numbers" should move, and in what direction;
- its cost: what it touches.

A proposal without evidence from this change is not a proposal. Never apply one.

## 7. Self-check and the report

1. The previous retro is the newest other file in `docs/retros/`, by `git log --diff-filter=A --format=%cs -- docs/retros/`. If there is none, write "none: this is the first".
2. A proposal of the previous retro counts as accepted when a merged `chore/*` PR cites it as `retro <previous-id> P<n>`: `gh pr list --state merged --search "retro <previous-id>" --json number,title,body,headRefName`.
3. For each accepted proposal, compare the number it targeted between the previous retro and this one.
4. If the previous retro also had 0 accepted proposals from its own predecessor, and this one finds 0 accepted from the previous retro, write: "Two retros in a row with no accepted proposal: recommend deleting /retro."
5. Write `docs/retros/$0.md` from `.claude/templates/retro.md`:
   - in plain words, about 60 lines at most;
   - only conclusions and numbers, never transcript excerpts, quotes or command output;
   - no secrets, credentials or personal data.

## 8. PR

1. `git switch -c chore/retro-$0`
2. `git add docs/retros/$0.md` (that file only) and `git commit -m "docs(retro): retrospective of $0"`.
3. `git push -u origin chore/retro-$0`
4. Open the PR:

```
gh pr create --base main --head chore/retro-$0 --title "docs(retro): retrospective of $0" --body-file - <<'EOF'
## Summary

<Three lines: the headline numbers and the top proposal.>

To adopt a proposal, open a later chore PR whose title or body cites `retro $0 P<n>`. The next retro counts it as accepted.
EOF
```

## 9. Finish

End with one line: the PR link, the number of proposals, and what comes next: Cristian reads the retro, ships it with `/ship <pr>`, and decides which proposals become a chore PR. Then stop.
