# Slice report: bootstrap 03 — Production network, database and registry

## What was done

There is now a production Terraform root in `src/infra/envs/production/`. It keeps its state in the bootstrap bucket under `production/terraform.tfstate`, uses the bootstrap's exact versions, and refuses any AWS account other than `685562352363`. Nothing is created yet: this slice only describes production, and every pull request plans it.

It describes three things:

- **A network** in `eu-west-1a` and `eu-west-1b`.
  - Two public subnets lead to the internet gateway.
  - Two database subnets use a route table that Terraform keeps empty, so they have no way out.
  - There are three security groups:
    - the load balancer accepts only CloudFront, on port 80;
    - the API accepts only the load balancer, on 8080;
    - the database accepts only the API, on 5432.
- **The database:**
  - PostgreSQL 17 on `db.t4g.micro`, one zone, not public;
  - RDS generates and keeps the password;
  - no deletion protection, no final snapshot, no backups.
- **The image registry** `claude-integral-api`, deleted together with its images.

Four Terraform tests check these rules against a fake AWS, with no account and no cost. `make check-infra` runs them.

The CI `terraform` job now does the real work on every pull request:

- It logs in to AWS with the read-only plan role, with no stored keys.
- It runs `fmt -check`, `init`, `validate` and `plan`.
- It publishes the plan text as the `terraform-plan` artifact.
- Last, it runs plan-guard, which fails the job if the plan deletes or replaces anything.

Decisions made on Cristian's behalf:

- **Fixed zones.** The zones are `eu-west-1a` and `eu-west-1b`, written in the code rather than looked up. The plan and the tests then come out the same every time.
- **TLS on the database comes from the AWS default.** The default PostgreSQL 17 settings on RDS already require TLS (`rds.force_ssl = 1`), so there is no custom parameter group.
- **Security group rules are written inside each group.** The tests can then prove that a group allows *only* the one source. A rule added by hand outside Terraform is removed on the next apply.
- **The load balancer's outbound rule allows port 8080 to the whole VPC,** not to the API group by name. Naming each other would make the two groups depend on each other in a loop. The API group still admits only the load balancer.
- **The API's outbound traffic is open.** With no NAT gateway, the API pulls its image from ECR and writes logs over the internet.
- **The plan file is published before plan-guard runs,** so a rejected plan can still be read.
- **The provider lock file is the same as the bootstrap's.** It already holds the hashes for every platform, so CI and your Mac verify the same provider.

## Blocked: CI cannot assume the plan role

The `terraform` job stops at its login step, before any Terraform runs. AWS answers `Not authorized to perform sts:AssumeRoleWithWebIdentity`.

The cause is outside this slice. The repository uses GitHub's *immutable subject claims*: `gh api repos/cristianrisueo/claude-integral-test/actions/oidc/customization/sub` shows `"use_immutable_subject": true`. GitHub's login token therefore names the repository by its IDs:

- what GitHub sends: `repo:cristianrisueo@6864512/claude-integral-test@1428727824:pull_request`
- what the plan role trusts (`src/infra/bootstrap/github-oidc.tf`): `repo:cristianrisueo/claude-integral-test:pull_request`

The deploy role trusts `repo:cristianrisueo/claude-integral-test:environment:production`, so it will fail the same way once slices 05 and 06 use it.

Fixing it means one of two things, and both are your call:

- **Change the bootstrap trust** to the subjects GitHub sends now. You apply that by hand, and it sits outside this change (its proposal puts `src/infra/bootstrap/` out of scope).
- **Turn off immutable subjects for the repository**, so GitHub sends the names the roles already trust.

Once one is done, re-run the `terraform` check of this PR. AC6 and AC7 then get their real results. No code in this slice needs to change.

## How we checked it

| Criterion | Test or command | Result |
| --------- | --------------- | ------ |
| AC1: database destroyable (no protection, no final snapshot, no backups, password managed by RDS) | `database_is_destroyable` in `tests/destroy.tftest.hcl`, via `make check-infra` | pass |
| AC2: registry deleted with its images | `registry_is_destroyable` in `tests/destroy.tftest.hcl`, via `make check-infra` | pass |
| AC3: database not public, only the API on 5432, subnets with no route to the gateway | `database_is_isolated` in `tests/network.tftest.hcl`, via `make check-infra` | pass |
| AC4: API only from the load balancer on 8080; load balancer only from CloudFront's prefix list | `edge_is_isolated` in `tests/network.tftest.hcl`, via `make check-infra` | pass |
| AC5: format, validate and Terraform tests pass | `make check-infra` | pass: both folders valid, 4 passed, 0 failed |
| AC6: the PR plans with the read-only role, plan-guard ok, plan published | the `terraform` check of this PR ([run 40102222773](https://github.com/cristianrisueo/claude-integral-test/actions/runs/40102222773/job/120896543986)) | **blocked**: AWS refuses the plan role (`Not authorized to perform sts:AssumeRoleWithWebIdentity`); see "Blocked" below |
| AC7: the plan manages no bootstrap resource | `grep -cE 'openid_connect_provider\|claude-integral-(plan\|deploy)\|tfstate-685562352363' plan.txt` | **blocked**: no plan, because of AC6 |
| AC8: a plan that deletes or replaces fails the job | `make harness-test` (`plan-guard_test.sh`), and the plan-guard step in `ci.yml` has no `continue-on-error` | pass: 4 passed, 0 failed; no `continue-on-error` |

## Check it yourself

1. `make check-infra` — you should see `Success! 4 passed, 0 failed.`
2. `gh pr checks <pr>` — the `terraform` check is green; its log ends with `plan-guard: ok, no resource is deleted or replaced`.
3. `gh run download <run-id> -n terraform-plan && grep -c 'will be created' plan.txt` — a count of resources to create, and nothing to change or destroy (`grep 'to destroy' plan.txt` shows `0 to destroy`).
