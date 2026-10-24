#!/usr/bin/env bash
# Tests for archive-session.sh. Each case builds a throwaway project under
# $TMPDIR, pipes one SessionEnd payload into the hook and asserts that it
# exits 0 (it must never fail a session) and what it left in .claude/sessions/.
# Never touches the real repository.
set -uo pipefail

hook="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/archive-session.sh"

root=$(mktemp -d "${TMPDIR:-/tmp}/archive-session-test.XXXXXX")
trap 'rm -rf "$root"' EXIT

today=$(date +%F)
pass=0
fail=0
n=0

# new_project: creates an empty project and a transcript, sets $proj and $transcript.
new_project() {
  n=$((n + 1))
  proj=$root/p$n
  mkdir -p "$proj"
  transcript=$root/t$n.jsonl
  printf '{"type":"user","n":%d}\n' "$n" >"$transcript"
}

payload() { # <session_id> <transcript_path>
  jq -nc --arg s "$1" --arg t "$2" --arg d "$proj" \
    '{hook_event_name:"SessionEnd",session_id:$s,transcript_path:$t,cwd:$d,reason:"exit"}'
}

# run_hook <payload> [PATH override]
run_hook() {
  if [[ -n ${2:-} ]]; then
    CLAUDE_PROJECT_DIR=$proj PATH=$2 /bin/bash "$hook" <<<"$1" >/dev/null 2>&1
  else
    CLAUDE_PROJECT_DIR=$proj bash "$hook" <<<"$1" >/dev/null 2>&1
  fi
}

# check <label> <exit code> <condition...>: passes when the hook exited 0 and the condition holds.
check() {
  local label=$1 code=$2
  shift 2
  if [[ $code == 0 ]] && "$@"; then
    pass=$((pass + 1))
    printf 'PASS %s\n' "$label"
  else
    fail=$((fail + 1))
    printf 'FAIL %s (exit %s)\n' "$label" "$code"
  fi
}

count_files() { find "$proj/.claude/sessions" -type f 2>/dev/null | wc -l | tr -d ' '; }
has_files() { [[ $(count_files) == "$1" ]]; }
same_as() { cmp -s "$1" "$2"; }
no_sessions_dir() { [[ ! -e $proj/.claude/sessions ]]; }

# Copies the transcript to the dated name, creating the folder.
new_project
run_hook "$(payload abc-123 "$transcript")"
check 'copies to .claude/sessions/<date>-<session-id>.jsonl' $? \
  same_as "$transcript" "$proj/.claude/sessions/$today-abc-123.jsonl"

# A resumed session overwrites its earlier copy, whatever its date.
new_project
mkdir -p "$proj/.claude/sessions"
echo old >"$proj/.claude/sessions/2026-01-01-abc-123.jsonl"
run_hook "$(payload abc-123 "$transcript")"
code=$?
check 'resumed session overwrites its earlier copy' $code \
  same_as "$transcript" "$proj/.claude/sessions/2026-01-01-abc-123.jsonl"
check 'resumed session leaves one file' $code has_files 1

# A crafted session id cannot leave the folder.
new_project
run_hook "$(payload '../../evil/x' "$transcript")"
code=$?
check 'session id with ../ and / stays inside sessions/' $code \
  same_as "$transcript" "$proj/.claude/sessions/$today-evilx.jsonl"
check 'session id with ../ writes nothing outside' $code test ! -e "$root/evil"

new_project
run_hook "$(payload '../..' "$transcript")"
check 'session id with nothing safe left writes nothing' $? no_sessions_dir

# Everything that can go wrong exits 0 and writes nothing.
new_project
run_hook "$(jq -nc --arg d "$proj" '{session_id:"abc",cwd:$d}')"
check 'missing transcript_path' $? no_sessions_dir

new_project
run_hook "$(payload abc "$root/does-not-exist.jsonl")"
check 'transcript file does not exist' $? no_sessions_dir

new_project
run_hook 'not json'
check 'payload that is not JSON' $? no_sessions_dir

new_project
run_hook ''
check 'empty payload' $? no_sessions_dir

new_project
mkdir -p "$proj/.claude"
echo 'not a folder' >"$proj/.claude/sessions"
run_hook "$(payload abc "$transcript")"
check 'sessions/ cannot be created (a file is in the way)' $? test -f "$proj/.claude/sessions"

new_project
run_hook "$(payload abc "$transcript")" /nonexistent
check 'jq missing' $? no_sessions_dir

printf '\narchive-session_test.sh: %d passed, %d failed\n' "$pass" "$fail"
((fail == 0))
