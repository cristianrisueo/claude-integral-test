# GitHub Actions authenticates to AWS through OIDC: no stored keys. Each role
# trusts exact subjects of this repository only (no wildcards).

locals {
  oidc_host = "token.actions.githubusercontent.com"
}

# No thumbprint_list: AWS validates GitHub's certificate against its own
# trusted CA library, so the provider no longer requires one.
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://${local.oidc_host}"
  client_id_list = ["sts.amazonaws.com"]
}

# --- Plan role: pull requests and main, read-only ---------------------------

data "aws_iam_policy_document" "plan_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values = [
        "repo:${local.repo}:pull_request",
        "repo:${local.repo}:ref:refs/heads/main",
      ]
    }
  }
}

resource "aws_iam_role" "plan" {
  name                 = "claude-integral-plan"
  description          = "terraform plan from GitHub Actions (pull requests and main)"
  assume_role_policy   = data.aws_iam_policy_document.plan_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "plan_read_only" {
  role       = aws_iam_role.plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# ReadOnlyAccess cannot write, but terraform plan creates and deletes the
# <key>.tflock file next to the state (use_lockfile). It never writes the
# state itself, so writes are limited to lock files.
data "aws_iam_policy_document" "plan_state" {
  statement {
    sid       = "ListStateBucket"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]
  }

  statement {
    sid       = "ReadStateObjects"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.state.arn}/*"]
  }

  statement {
    sid       = "WriteLockFiles"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.state.arn}/*.tflock"]
  }
}

resource "aws_iam_role_policy" "plan_state" {
  name   = "terraform-state"
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.plan_state.json
}

# --- Deploy role: the production environment only, full access -------------

data "aws_iam_policy_document" "deploy_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = ["repo:${local.repo}:environment:production"]
    }
  }
}

resource "aws_iam_role" "deploy" {
  name                 = "claude-integral-deploy"
  description          = "terraform apply from GitHub Actions (production environment)"
  assume_role_policy   = data.aws_iam_policy_document.deploy_trust.json
  max_session_duration = 3600
}

# Trade-off: AdministratorAccess instead of a least-privilege policy.
# terraform apply creates and changes IAM roles, ECS, ALB, RDS, ECR, S3 and
# CloudFront; a hand-written policy covering that is long, breaks with every
# new resource type, and IAM write access is already close to admin anyway.
# The risk is held by who can assume the role, not by what it can do:
#   - only jobs in the GitHub environment "production" (the exact sub above),
#     never a pull request or an arbitrary branch;
#   - that environment requires Cristian's approval before the job starts;
#   - no stored keys: short-lived OIDC credentials, sessions of at most 1 h.
# Narrowing this to the services the stack uses is a follow-up change.
resource "aws_iam_role_policy_attachment" "deploy_admin" {
  role       = aws_iam_role.deploy.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
