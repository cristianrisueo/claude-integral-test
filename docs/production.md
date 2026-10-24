# Production

Production is short-lived. Three GitHub workflows create it, check it and remove it, in AWS `eu-west-1`. While it is up, it costs about $1.7 a day.

The site lives at `https://<id>.cloudfront.net`. The address changes each time production is re-created. `terraform output -raw url` in `src/infra/envs/production/` prints it, and every deploy and verify run shows it in its summary.

`cd.yml` and `destroy.yml` share the `production` concurrency group. They never run at the same time, and a run waiting for approval is never cancelled: the next one queues behind it.

## Deploy: `cd.yml`

**When it runs:**

- on a push to `main` that changes `src/api/`, `src/web/`, `src/infra/envs/` or `cd.yml` itself;
- by hand, for example to re-create production after a destroy: `gh workflow run cd.yml --ref main`.

A merge that changes only docs, specs or harness files does not deploy.

**What happens:**

1. `plan` plans with the read-only role. The run summary shows the plan ("Production plan"). plan-guard then fails the run if the plan deletes or replaces anything. A deploy only adds or changes.
2. `deploy` waits for your approval in the `production` environment. Read the plan in the summary first. To keep production down, reject it; after a destroy, every merge that touches the paths above asks again.
3. After approval, `deploy` applies exactly that saved plan. It builds the API image with the commit SHA baked in and pushes it as `:<sha>` and `:live`. It restarts the ECS service and waits until it is stable. Then it publishes the web build and clears the CloudFront cache.
4. `verify` runs `verify.yml` with the commit just deployed (below).

**What a good run shows:** `plan`, `deploy` and `verify` green on attempt 1. The plan log ends with `plan-guard: ok, no resource is deleted or replaced`. From nothing, the plan creates 35 resources. Example: [run 40134431077](https://github.com/cristianrisueo/claude-integral-test/actions/runs/40134431077), which created production from nothing in about 13 minutes.

## Verify: `verify.yml`

**When it runs:** as the last job of every `cd.yml` run, and by hand at any time: `gh workflow run verify.yml --ref main`. It only reads, so it needs no approval.

**What it checks:**

1. It reads the site's address and the image registry from the production state.
2. It decides the expected version:
   - called by `cd.yml`: the commit `cd.yml` deployed;
   - by hand: the one commit SHA tag of the `:live` image in ECR. Main may be ahead of what is deployed, so it asks ECR instead. If `:live` has no SHA tag, or more than one, it fails and says which.
3. It waits up to 5 minutes for `/api/health` to answer 200 with database ok and that version. A deploy whose new task never started fails here, even though the old one still answers.
4. It runs the end-to-end suite against the site.

**What a good run shows:** a green `verify` job. Its log has `check-health: https://<id>.cloudfront.net/api/health answers 200, database ok, version <sha>` and `3 passed`. Its summary ("Verify") is a table: the site, the live version and the expected version, which must be equal.

A failed verify turns the run red. Nothing is rolled back: the summary shows which version is live, and you decide what to do next.

## Destroy: `destroy.yml`

**When it runs:** only by hand: `gh workflow run destroy.yml --ref main`.

**What happens:**

1. `plan` builds the destroy plan with the read-only role and shows it in the run summary.
2. `destroy` waits for your approval in the `production` environment. After approval, it applies exactly that plan, in one run.
3. It then fails unless `terraform state list` prints nothing ("State is empty") and the state bucket still exists ("State bucket still exists").

**What a good run shows:** `plan` and `destroy` green on attempt 1. The apply ends with `Apply complete! Resources: 0 added, 0 changed, N destroyed.` The last step prints the state bucket `claude-integral-test-tfstate-685562352363`. With nothing deployed, the plan shows nothing to destroy and the run still succeeds.

The bootstrap (the state bucket, the GitHub OIDC provider and the plan and deploy roles) is never touched. It lives in `src/infra/bootstrap/`, outside these workflows.

## When a run fails

- Open the run, then the red job, and read the first `Error:` in its log.
- A failed `deploy` can leave production half built. Either fix the code and merge, which plans and applies the rest, or run `destroy.yml` to start clean.
- Never apply or destroy from your machine. Every change to production goes through these workflows and your approval.

The first deploy is an example: [run 40130775930](https://github.com/cristianrisueo/claude-integral-test/actions/runs/40130775930) failed because AWS refused a load balancer check that counts 503 as healthy. The `liveness` change fixed it with `/api/live`, after a destroy cleaned up the half-built production.
