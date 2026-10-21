#!/usr/bin/env bash
# Fails when a Terraform plan deletes or replaces a resource, listing their
# addresses. A replacement shows up as "delete" in the actions, so it fails too.
#
# Usage: tools/plan-guard.sh <plan.json>    (from: terraform show -json <planfile>)
set -uo pipefail

plan=${1:?usage: plan-guard.sh <plan.json>}
if ! command -v jq >/dev/null 2>&1; then
  echo "plan-guard: jq is required" >&2
  exit 2
fi

if ! jq -e 'type == "object"' "$plan" >/dev/null 2>&1; then
  echo "plan-guard: cannot read '$plan' as a Terraform JSON plan" >&2
  exit 2
fi
addresses=$(jq -r '.resource_changes[]? | select(.change.actions | index("delete")) | .address' "$plan")

if [[ -n $addresses ]]; then
  echo "plan-guard: the plan deletes or replaces these resources:" >&2
  sed 's/^/  - /' <<<"$addresses" >&2
  exit 1
fi
echo "plan-guard: ok, no resource is deleted or replaced"
