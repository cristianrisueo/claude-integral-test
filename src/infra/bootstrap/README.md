# AWS bootstrap (one time, by hand)

This Terraform root creates what CI/CD needs before any other infrastructure exists. It lives in account `685562352363`, region `eu-west-1`.

| Resource | Name |
| --- | --- |
| State bucket | `claude-integral-test-tfstate-685562352363`, with versioning, SSE-S3, public access blocked, TLS required and `prevent_destroy` |
| GitHub OIDC provider | `token.actions.githubusercontent.com`, audience `sts.amazonaws.com` |
| Plan role | `claude-integral-plan`: `ReadOnlyAccess`, plus read on the state objects, write only on lock files. Trusted for pull requests and `main`, with the repository named either by name or by its immutable IDs |
| Deploy role | `claude-integral-deploy`: `AdministratorAccess`. Trusted only for the `production` environment, in both subject forms (the trade-off is explained in `github-oidc.tf`) |

Cristian runs it once from his machine. CI validates it (`make check-infra`) but never plans or applies it, and `plan-guard` never sees it. Claude never runs `plan` or `apply` here.

## Before you start

- Terraform `1.15.3` (`terraform version`), the AWS CLI v2 and `gh` (`gh auth status`).
- An AWS SSO profile with administrator rights in account `685562352363`. Below it is called `<profile>`.
- A GitHub environment named `production` with you as a required reviewer (Settings → Environments). The deploy role can only be assumed by jobs in that environment.

## 1. Log in to AWS

```sh
aws sso login --profile <profile>
export AWS_PROFILE=<profile>
aws sts get-caller-identity --query Account --output text   # must print 685562352363
```

## 2. Create the resources (local state)

From the repository root:

```sh
cd src/infra/bootstrap
terraform init
terraform plan -out=bootstrap.tfplan
terraform apply bootstrap.tfplan
```

Read the plan before applying. It should only create these resources: the bucket and its versioning, encryption, public access block and policy, the OIDC provider, the two roles, their three policy attachments and the inline state policy.

## 3. Move this state into the bucket (done)

The migration is done. The state lives in `s3://claude-integral-test-tfstate-685562352363/bootstrap/terraform.tfstate`, and `backend.tf` in this folder is committed. Later runs only need:

```sh
terraform init        # reads the state from the bucket
```

## 4. Give CI the outputs

Still in `src/infra/bootstrap`:

```sh
gh variable set AWS_PLAN_ROLE_ARN   --repo cristianrisueo/claude-integral-test --body "$(terraform output -raw plan_role_arn)"
gh variable set AWS_DEPLOY_ROLE_ARN --repo cristianrisueo/claude-integral-test --body "$(terraform output -raw deploy_role_arn)"
gh variable set TF_STATE_BUCKET     --repo cristianrisueo/claude-integral-test --body "$(terraform output -raw state_bucket)"
gh variable list --repo cristianrisueo/claude-integral-test
```

These are variables, not secrets: role ARNs and a bucket name grant nothing without the OIDC trust.

## Later changes

- Change this root by hand the same way: `terraform init`, `terraform plan`, read the plan, then `terraform apply`.
- The bucket has `prevent_destroy`, so `terraform destroy` fails. Deleting it would lose every state of the project.
