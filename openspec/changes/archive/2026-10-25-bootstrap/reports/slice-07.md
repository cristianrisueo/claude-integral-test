# Slice report: bootstrap 07 — Round trip

## What was done

Real runs in GitHub deployed production from nothing, verified it twice and destroyed it twice. Production is now destroyed, and the bootstrap is intact. No workflow or infrastructure code changed.

The runs:

| # | Run | What it did | Result |
| - | --- | ----------- | ------ |
| 1 | [cd.yml 40130775930](https://github.com/cristianrisueo/claude-integral-test/actions/runs/40130775930) | merge of #21 (slice 06), commit 1228d18 | **failed** in `deploy`: AWS refused the load balancer check |
| 2 | [destroy.yml 40132401652](https://github.com/cristianrisueo/claude-integral-test/actions/runs/40132401652) | dispatched by you after run 1 | success: 32 destroyed, state empty, state bucket found |
| 3 | [cd.yml 40134431077](https://github.com/cristianrisueo/claude-integral-test/actions/runs/40134431077) | merge of #23 (liveness), commit 91eb4ed, from nothing | success: 35 created, deployed, verified |
| 4 | [verify.yml 40136381478](https://github.com/cristianrisueo/claude-integral-test/actions/runs/40136381478) | dispatched in this slice | success: version read from ECR, both checks passed |
| 5 | [destroy.yml 40136588749](https://github.com/cristianrisueo/claude-integral-test/actions/runs/40136588749) | dispatched in this slice | success: 35 destroyed, state empty, state bucket found |

Then:

- `docs/production.md` explains how to deploy, verify and destroy, what each run shows, and what to do when one fails.
- The five delta specs are merged into `openspec/specs/`. `delivery`, `local-stack` and `status-page` are new. `health` and `production` already held the liveness requirements; bootstrap's requirements are appended after them. Every bootstrap delta only adds, and none contradicts liveness.
- The change is archived as `openspec/changes/archive/2026-10-25-bootstrap/`.

**Deviations from `tasks.md`** (you asked for this shortened round trip):

- **Run 1 failed, so AC1 is covered by run 3.** The first deploy stopped at the target group: `ValidationError: Health check matcher HTTP code '503' must be within '200-499' inclusive` (`edge.tf` line 21, `aws_lb_target_group.api`). The slice stopped there, as it says to. The fix was a new change, [liveness](../../2026-10-24-liveness/proposal.md) (#22, #23): the load balancer now checks `/api/live` with 200.
- **AC2 destroyed a half-built production.** Run 2 removed what run 1 had created before it failed (32 resources), at commit 1228d18.
- **AC3 was started by a push, not a dispatch.** The merge of #23 changed `src/api/` and triggered `cd.yml` while production was destroyed. So run 3 is both "the merge deploys and verifies" (AC1) and "from nothing" (AC3), and it runs the merge commit. `cd.yml` was not dispatched again.
- **AC4 and AC5 are checked from the run logs.** GitHub's API does not return a job's step summary, so the logs show the same values. The summaries are on the run pages.

Decisions made on Cristian's behalf:

- **The archive date is 2026-10-25,** the local date when archiving (`date +%F`). The runs are dated 2026-10-24 UTC.
- **Verify was dispatched from `main`** (91eb4ed, the commit `:live` was built from).
- **No red run.** This slice adds no code and no tests, so nothing could fail first. The PR description says so.

## How we checked it

| Criterion | Test or command | Result |
| --------- | --------------- | ------ |
| AC1: the merge deploy deployed and verified, running the merge commit | `gh run view 40134431077` (deviation: run 3 instead of run 1, which failed) | pass: `plan`, `deploy`, `verify` success on attempt 1, head 91eb4ed; verify log `check-health: … answers 200, database ok, version 91eb4ed32b76f56434f791528c993d8c0faaff59` |
| AC2: the first destroy deleted all of production, bootstrap intact | `gh run view 40132401652 --log` | pass: `destroy` success on attempt 1, `Apply complete! Resources: 0 added, 0 changed, 32 destroyed.`, "State is empty" passed, `head-bucket` found `claude-integral-test-tfstate-685562352363` |
| AC3: deploy from nothing, no collision, no manual step | `gh run view 40134431077` (deviation: pushed, not dispatched) | pass: plan `35 to add, 0 to change, 0 to destroy`, `plan-guard: ok`, every job success on attempt 1, live version = head SHA 91eb4ed |
| AC4: manual verify read the version from ECR and passed | `gh run view 40136381478 --log` | pass: success on attempt 1; `INPUT` empty, so ECR was asked; `EXPECTED: 91eb4ed…`, `check-health: … version 91eb4ed…`, `3 passed`; equal to the head SHA of run 3 |
| AC5: page and API on one HTTPS address | the logs of runs 3 and 4 | pass: both use `https://d17tukdzmh7gko.cloudfront.net`, health and e2e (3 passed) green in both |
| AC6: the second destroy left production destroyed, bootstrap intact | `gh run view 40136588749 --log` | pass: `destroy` success on attempt 1, plan `35 to destroy`, `Apply complete! … 35 destroyed.`, "State is empty" passed, state bucket found |
| AC7: no workflow or infrastructure code changed | `git diff --stat origin/main...HEAD -- .github src/infra` | pass: prints nothing |
| AC8: specs merged, change archived | `make spec-lint`, `ls openspec/specs` | pass: `spec-lint: ok`; delivery, health, local-stack, production, status-page |

`make check` (harness tests: 81 + 12 + 8 + 4 passed, 0 failed; spec-lint tests ok; gofmt, vet, lint and typecheck clean) and `make test` (Go: 2 packages ok; web: 5 passed) are green. `make check-infra` and `make e2e` were not run: nothing in `src/` changed, and the e2e suite ran against production in runs 3 and 4.

## Check it yourself

1. `gh run view 40136381478 --log | grep -E 'EXPECTED:|check-health:'` — the expected version from ECR and the live version are both `91eb4ed32b76f56434f791528c993d8c0faaff59`.
2. `gh run view 40136588749 --log | grep -E 'destroyed\.|BucketArn'` — `35 destroyed.` and the state bucket's ARN.
3. `make spec-lint && ls openspec/specs openspec/changes/archive` — `spec-lint: ok`, five capabilities, and `2026-10-25-bootstrap` beside `2026-10-24-liveness`.
