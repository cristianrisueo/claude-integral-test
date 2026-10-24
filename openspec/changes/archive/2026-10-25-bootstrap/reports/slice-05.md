# Slice report: bootstrap 05 — Destroy workflow

## What was done

There is now a `destroy.yml` workflow. You start it by hand from the Actions tab, and it removes production in one run. Nothing has run yet: the workflow can only be started once it is on main, and its first runs are slice 07's.

It has two jobs:

- **`plan`** logs in with the read-only plan role.
  - It makes a destroy plan of `src/infra/envs/production/`.
  - It shows the plan text in the run summary.
  - It saves the plan file as the `destroy-plan` artifact.
- **`destroy`** runs in the `production` environment, so it waits for your approval.
  - It logs in with the deploy role and applies that saved plan, not a new one.
  - Then it fails unless `terraform state list` prints nothing and the state bucket still answers `head-bucket`.

The workflow is in the concurrency group `production` and never cancels a run in progress. Once `cd.yml` joins the same group in slice 06, a destroy and a deploy can never overlap. A run waiting for your approval still holds the group, so nothing can change production between the plan you read and the apply you approve. Terraform also refuses a saved plan whose state has changed.

Decisions made on Cristian's behalf:

- **Built alongside slice 04.** You waived the precondition that slice 04's report exists. The two slices touch different files.
- **The state bucket name is written in the workflow,** copied from `backend.tf`. If the bucket is ever renamed, both places change.
- **The saved plan is kept for 1 day.** The repository is public, so any signed-in GitHub user can download a run's artifacts. A plan file carries a copy of the production state. That state holds IDs and ARNs but no password, because RDS keeps the database password itself. One day is enough to approve the run.
- **No plan-guard in this workflow.** plan-guard rejects deletions, and a destroy is nothing but deletions. `fmt` and `validate` are also left out, because CI already runs them on every pull request.
- **The plan is shown in the run summary as a plain text block.** You read it there before approving.
- **"Nothing deployed" needs no special case.** With production already gone, the plan is empty and the apply does nothing. `state list` then prints nothing, and the run is green.
- **`actions/download-artifact@v8`.** It is the current major version and reads what `upload-artifact@v7` writes.

## How we checked it

| Criterion | Test or command | Result |
| --------- | --------------- | ------ |
| AC1: the workflow is valid | `docker run --rm -v "$PWD":/repo -w /repo rhysd/actionlint:1.7.7 .github/workflows/destroy.yml` | pass: no output, exit 0 |
| AC2: manual dispatch only; only `destroy` runs in `production`, after `plan` | `grep -nE '^on:\|workflow_dispatch\|environment:\|needs:' .github/workflows/destroy.yml` | pass: `workflow_dispatch` is the only trigger; `needs: plan` (line 65) and `environment: production` (line 69) are both in `destroy` |
| AC3: plan role in `plan`, deploy role in `destroy` | `grep -n 'role-to-assume' .github/workflows/destroy.yml` | pass: `vars.AWS_PLAN_ROLE_ARN` (line 36, `plan`); `vars.AWS_DEPLOY_ROLE_ARN` (line 80, `destroy`) |
| AC4: `destroy` applies the saved destroy plan | `grep -nE 'plan -destroy\|apply' .github/workflows/destroy.yml` | pass: `plan -destroy … -out=destroy.tfplan` (line 44); `apply … destroy.tfplan` (line 93) |
| AC5: after the apply, state empty and state bucket present | `grep -nE 'state list\|head-bucket' .github/workflows/destroy.yml` | pass: `state list` (line 96) and `head-bucket` (line 105), both in `destroy`, after the apply |
| AC6: group `production`, never cancels a run in progress | `grep -nA2 '^concurrency:' .github/workflows/destroy.yml` | pass: `group: production`, `cancel-in-progress: false` |
| AC7: CI stays green | `gh pr checks <pr>` | checked on this PR; `/ship` waits for every check to be green before it asks you |

`make check` (harness tests: 105 passed, 0 failed; lint and typecheck clean) and `make test` (Go: 2 packages ok; web: 5 passed) are green.

## Check it yourself

1. `docker run --rm -v "$PWD":/repo -w /repo rhysd/actionlint:1.7.7 .github/workflows/destroy.yml` — prints nothing.
2. `grep -nE '^on:|workflow_dispatch|environment:|needs:' .github/workflows/destroy.yml` — shows `workflow_dispatch` under `on:`, then `needs: plan` and `environment: production`, both in the `destroy` job.
3. `grep -nA2 '^concurrency:' .github/workflows/destroy.yml` — shows `group: production` and `cancel-in-progress: false`.
