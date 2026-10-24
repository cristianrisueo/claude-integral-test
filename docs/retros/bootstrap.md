# Retro: bootstrap

2026-10-25 · PRs: #7 propose, #9 slice 01, #12 slice 02, #14 slice 03, #18 slice 04, #17 slice 05, #21 slice 06, #25 slice 07 · Transcripts: 9 sessions (7 for the change, 2 chore `/ship` sessions that touched it)

## Numbers

| Measure                       | Value                                   | Source                          |
| ----------------------------- | --------------------------------------- | ------------------------------- |
| Slices                        | 7                                       | tasks.md                        |
| First-pass audit approvals    | 5 of 7 (01, 03, 04, 05, 06); 02 never audited; 07 changes requested | audit comments |
| Fix rounds                    | 0 (07's two blocking findings were overridden by Cristian at `/ship`) | audit comments |
| Halted slices                 | 0                                       | audit comments                  |
| Guard blocks                  | 1 (G5: 1, slice 07 archive move)        | transcripts                     |
| Stop-hook pushbacks           | 0                                       | transcripts                     |
| Permission prompts declined   | 0, approximate                          | transcripts                     |
| Unsandboxed retries           | 126 (`gh` 79, terraform/check-infra 18, docker/e2e 13, git network 7, make/go test 4, other 5) | transcripts |
| CI failures                   | 6 (terraform on slice 03: 5 attempts, CI setup, OIDC subject claims; CD on main: 1, terraform apply, run 40130775930) | gh run list |
| Debt issues opened            | 4 (#10, #16, #19, #20), all open        | gh issue list                   |
| Time per slice, approximate   | propose: PR 69 min, session 91 min; 01: 10 / 77 min; 02: 9 / 25 min; 03: 27 / 38 min; 04: 61 min and 05: 7 min, one 85 min session; 06: 3 h 36 min / about 5 h; 07: 7 / 24 min | PR dates, transcripts |

## What worked

- The audit was clean where it ran: 5 first-pass approvals and no fix round across six infra and workflow slices.
- The audit caught real gaps in slice 07 (2 acceptance criteria not met as written), and the override was recorded on PR #25.
- Slice 07 stopped on the failed first deploy, as the proposal said. The fix became its own change (liveness, #22 and #23), and the second round trip was green on attempt 1 in every run.
- Every destroy left the state empty and the state bucket intact (runs 40132401652 and 40136588749).
- Debt went to issues, not into the code: 4 non-blocking findings became #10, #16, #19 and #20.
- The proposal interview asked 8 questions, and none of the 19 questions in the change re-asked something already written in the repo.

## Friction

- The 503 health-check matcher passed the proposal, the mocked Terraform tests, plan-guard and two audit rounds, then AWS rejected it on the first real deploy. It cost a whole new change and most of slice 06's 5-hour session. Evidence: run 40130775930, proposal "One health endpoint", PR #18.
- Slice 02 merged with no audit verdict, and the decision is recorded nowhere on the PR. The audit job skipped silently because the PR edited `ci.yml`. #13 fixed the cause and allowed a dispatch for #12, but #12 was never audited. Evidence: PR #12 (0 comments), PR #13.
- The audit cannot open workflow runs or download the plan artifact, so slice 07, whose evidence is all runs, was taken from the report. Evidence: PR #25 audit note.
- `gh` fails TLS verification in the sandbox (x509 OSStatus -26276), so 79 calls were retried unsandboxed. Evidence: transcripts, all 8 sessions that called `gh`.
- G5 blocked the allowed archive move because the destination used `$(date +%F)`. The local date also made the archive 2026-10-25 while the runs were 2026-10-24 UTC. Evidence: session of PR #25, audit finding 4.
- Slice 03's first terraform runs failed on GitHub's immutable OIDC subject claims, a one-time bootstrap issue fixed by #15.
- Rules that never fired: G1, G2, G3, G4, G6, G7, the Stop hook, the CI jobs harness, spec, checks and e2e, plan-guard rejecting a plan, and the audit's `CLAUDE.md` class. G1 to G4 and plan-guard guard rare but costly mistakes and still earn their place; G6 has no migrations to guard yet. None looks like noise. The round-2 re-audits of #14 and #18 ran on report-only commits and found nothing new.

## Proposed changes

Ordered by value. None of them is applied by the retro.

| ID  | Change   | Evidence           | Expected effect               | Cost             |
| --- | -------- | ------------------ | ----------------------------- | ---------------- |
| P1  | `/propose` and `/build` list every non-default AWS setting the design relies on, each with the provider doc that allows it, in the proposal and slice report | run 40130775930; liveness change #22, #23 | CD failures on a first deploy: 1 → 0; time on slice 06 down | small: two skill texts |
| P2  | `/ship` posts a decision comment whenever Cristian merges a `feat/*` PR without `APPROVED`, as was done by hand on #25 | PR #12 (no verdict, no record), PR #25 | Merged slices with no verdict and no recorded decision: 1 → 0 | small: ship skill |
| P3  | Give the audit read-only `gh run view` and `gh run download` | PR #25 audit note | Criteria the audit took on trust: slice 07's 6 run-based criteria → 0 | small: `audit.yml` and the audit skill |
| P4  | Let `gh` verify TLS inside the sandbox (only `gh`; Cristian weighs the wider access) | 79 unsandboxed `gh` retries | Unsandboxed retries: 126 → about 47; fewer prompts | small: `.claude/settings.json` |
| P5  | Archive with a literal UTC date (`date -u +%F` run first, then `git mv` with the value), or let G5 accept the substitution | 1 G5 block, PR #25 finding 4 | Guard blocks: 1 → 0; no date mismatch finding | small: build skill, or `guard.sh` and its test |

## Self-check

- Previous retro: none: this is the first.
- Accepted from it: not applicable.
- Did they help: not applicable.
