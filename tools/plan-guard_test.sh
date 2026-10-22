#!/usr/bin/env bash
# Tests for plan-guard.sh against the JSON plan fixtures in testdata/plan-guard/.
set -uo pipefail

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
guard=$dir/plan-guard.sh
fixtures=$dir/testdata/plan-guard

pass=0
fail=0

# check <expected exit code> <fixture>
check() {
  local want=$1 fixture=$2 code
  bash "$guard" "$fixtures/$fixture" >/dev/null 2>&1
  code=$?
  if ((code == want)); then
    pass=$((pass + 1))
    printf 'PASS exit %s %s\n' "$want" "$fixture"
  else
    fail=$((fail + 1))
    printf 'FAIL exit %s %s (got %s)\n' "$want" "$fixture" "$code"
  fi
}

check 0 create.json
check 0 update.json
check 1 replace.json
check 2 does-not-exist.json

printf '\nplan-guard_test.sh: %d passed, %d failed\n' "$pass" "$fail"
((fail == 0))
