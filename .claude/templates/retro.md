# Retro: <change-id>

<YYYY-MM-DD> · PRs: <#n propose, #n slice 01, …> · Transcripts: <N sessions | none, so GitHub and the reports only>

## Numbers

| Measure                       | Value                                   | Source                          |
| ----------------------------- | --------------------------------------- | ------------------------------- |
| Slices                        | <n>                                     | tasks.md                        |
| First-pass audit approvals    | <x of n>                                | audit comments                  |
| Fix rounds                    | <n> (<slices>)                          | audit comments                  |
| Halted slices                 | <n> (<slices, why>)                     | audit comments                  |
| Guard blocks                  | <n> (<G-rule: count, …>)                | transcripts                     |
| Stop-hook pushbacks           | <n>                                     | transcripts                     |
| Permission prompts declined   | <n, approximate>                        | transcripts                     |
| Unsandboxed retries           | <n> (<what for>)                        | transcripts                     |
| CI failures                   | <n> (<job: cause, …>)                   | gh run list                     |
| Debt issues opened            | <n> (<#issue, …>)                       | gh issue list                   |
| Time per slice, approximate   | <NN: PR open→merge; session span, …>    | PR dates, transcripts           |

<Write "unknown" for any value without a source. Never guess.>

## What worked

- <What went well, in plain words, and the number or PR that shows it.>

## Friction

- <Where Claude got stuck, what it asked that it could have read in a file, or a rule that never fired.> Evidence: <PR #, run id, report, rule>.

## Proposed changes

Ordered by value. None of them is applied by the retro.

| ID  | Change   | Evidence           | Expected effect               | Cost             |
| --- | -------- | ------------------ | ----------------------------- | ---------------- |
| P1  | <change> | <PR #, run, rule>  | <which number moves, and how> | <small \| medium \| large: what it touches> |

## Self-check

- Previous retro: <change-id, or "none: this is the first">.
- Accepted from it: <k of n> (<P-id: PR #, …>).
- Did they help: <for each accepted proposal, the number it targeted, before → after>.
- <Only when this retro and the previous one both accepted nothing: "Two retros in a row with no accepted proposal: recommend deleting /retro.">
