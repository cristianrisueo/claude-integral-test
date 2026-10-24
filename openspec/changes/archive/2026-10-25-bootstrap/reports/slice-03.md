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

## The first CI runs failed on the login, and what fixed it

The first two runs of the `terraform` check stopped at the AWS login: `Not authorized to perform sts:AssumeRoleWithWebIdentity`. Nothing in this slice was wrong. The repository uses GitHub's immutable subject claims, so GitHub names it by its IDs (`repo:cristianrisueo@6864512/claude-integral-test@1428727824:pull_request`), while the plan role trusted only the name form.

PR #15 (`chore/oidc-subjects`, outside this change) made both roles trust both forms, and you applied it by hand. The failed check was then re-run with no change to this slice's code. The deploy role needed the same fix, and it has it, so slices 05 and 06 are not affected.

## How we checked it

| Criterion | Test or command | Result |
| --------- | --------------- | ------ |
| AC1: database destroyable (no protection, no final snapshot, no backups, password managed by RDS) | `database_is_destroyable` in `tests/destroy.tftest.hcl`, via `make check-infra` | pass |
| AC2: registry deleted with its images | `registry_is_destroyable` in `tests/destroy.tftest.hcl`, via `make check-infra` | pass |
| AC3: database not public, only the API on 5432, subnets with no route to the gateway | `database_is_isolated` in `tests/network.tftest.hcl`, via `make check-infra` | pass |
| AC4: API only from the load balancer on 8080; load balancer only from CloudFront's prefix list | `edge_is_isolated` in `tests/network.tftest.hcl`, via `make check-infra` | pass |
| AC5: format, validate and Terraform tests pass | `make check-infra` | pass: both folders valid, 4 passed, 0 failed |
| AC6: the PR plans with the read-only role, plan-guard ok, plan published | the `terraform` check of this PR ([run 40102537505](https://github.com/cristianrisueo/claude-integral-test/actions/runs/40102537505/job/120901176657)); `gh run download 40102537505 -n terraform-plan` | pass: the job assumed the plan role; `Plan: 19 to add, 0 to change, 0 to destroy.`; `plan-guard: ok, no resource is deleted or replaced`; the artifact holds `plan.txt` |
| AC7: the plan manages no bootstrap resource | `grep -cE 'openid_connect_provider\|claude-integral-(plan\|deploy)\|tfstate-685562352363' plan.txt` on that artifact | pass: prints `0` |
| AC8: a plan that deletes or replaces fails the job | `make harness-test` (`plan-guard_test.sh`), and the plan-guard step in `ci.yml` has no `continue-on-error` | pass: 4 passed, 0 failed; no `continue-on-error` |

## Check it yourself

1. `make check-infra` — you should see `Success! 4 passed, 0 failed.`
2. `gh pr checks <pr>` — the `terraform` check is green; its log ends with `plan-guard: ok, no resource is deleted or replaced`.
3. `gh run download 40102537505 -n terraform-plan && grep '^Plan:' plan.txt` — you should see `Plan: 19 to add, 0 to change, 0 to destroy.`
