#!/usr/bin/env bash
# Tests for change-guard.sh in throwaway git repositories under $TMPDIR.
set -uo pipefail

guard="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/change-guard.sh"
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GITHUB_HEAD_REF

repo=$(mktemp -d "${TMPDIR:-/tmp}/change-guard-test.XXXXXX")
trap 'rm -rf "$repo"' EXIT

g() { git -C "$repo" -c core.hooksPath=/dev/null -c commit.gpgsign=false "$@"; }

g init -q
g symbolic-ref HEAD refs/heads/main
g config user.email change-guard-test@example.com
g config user.name change-guard-test
C=openspec/changes/demo
mkdir -p "$repo/$C/specs/users" "$repo/openspec/specs/users"
echo "# Proposal: demo, why and what" >"$repo/$C/proposal.md"
echo "# Design: demo, decisions and reasons" >"$repo/$C/design.md"
echo "# Tasks: demo, slice 01 and its criteria" >"$repo/$C/tasks.md"
echo "# Users delta: ADDED Create a user" >"$repo/$C/specs/users/spec.md"
echo "# Users specification today" >"$repo/openspec/specs/users/spec.md"
g add -A
g commit -q -m init

pass=0
fail=0

# check <pass|fail> <label> <branch> <change commands...>: branch off main,
# apply the change, commit, run the guard against main.
check() {
  local want=$1 label=$2 branch=$3 code
  shift 3
  g switch -q main
  g switch -q -c "$branch"
  (cd "$repo" && eval "$*")
  g add -A
  g commit -q -m "$label"
  (cd "$repo" && bash "$guard" main >/dev/null 2>&1)
  code=$?
  if { [[ $want == pass ]] && ((code == 0)); } || { [[ $want == fail ]] && ((code == 1)); }; then
    pass=$((pass + 1))
    printf 'PASS %-4s %s\n' "$want" "$label"
  else
    fail=$((fail + 1))
    printf 'FAIL %-4s %s (exit %s)\n' "$want" "$label" "$code"
  fi
}

check fail 'feat/*: modifying proposal.md' feat/demo-01 \
  "echo 'more scope' >> $C/proposal.md"
check fail 'feat/*: deleting tasks.md' feat/demo-02 \
  "git rm -q $C/tasks.md"
check fail 'feat/*: adding a spec to an approved change' feat/demo-03 \
  "mkdir -p $C/specs/orders && echo '# Orders delta' > $C/specs/orders/spec.md"
check fail 'feat/*: archive move that also edits a file' feat/demo-04 \
  "mkdir -p openspec/changes/archive && git mv $C openspec/changes/archive/2026-10-21-demo && echo edited >> openspec/changes/archive/2026-10-21-demo/design.md"
check fail 'feat/*: moving a change somewhere other than the archive' feat/demo-05 \
  "git mv $C openspec/changes/demo-renamed"
check pass 'feat/*: adding a slice report' feat/demo-06 \
  "mkdir -p $C/reports && echo '# Slice report 01' > $C/reports/slice-01.md"
check pass 'feat/*: archive move of the whole change folder' feat/demo-07 \
  "mkdir -p openspec/changes/archive && git mv $C openspec/changes/archive/2026-10-21-demo && mkdir -p openspec/changes/archive/2026-10-21-demo/reports && echo '# Slice report 02' > openspec/changes/archive/2026-10-21-demo/reports/slice-02.md && echo '### Requirement: Create a user' >> openspec/specs/users/spec.md"
check pass 'propose/*: modifying proposal.md is not checked' propose/demo \
  "echo 'reworded' >> $C/proposal.md"

printf '\nchange-guard_test.sh: %d passed, %d failed\n' "$pass" "$fail"
((fail == 0))
