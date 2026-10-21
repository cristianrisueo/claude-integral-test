#!/usr/bin/env bash
# PostToolUse formatter (Edit|Write). Formats the edited file by extension.
# A missing tool is a silent skip; a formatter or go vet failure exits 2 with
# the last 30 lines of its output.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
payload=$(cat)
project_dir=${CLAUDE_PROJECT_DIR:-$(pwd)}
file=$(jq -r '.tool_input.file_path // ""' <<<"$payload" 2>/dev/null)
[[ -n $file && -f $file ]] || exit 0
rel=${file#"$project_dir"/}

fail() {
  printf '%s failed on %s:\n' "$1" "$rel" >&2
  tail -n 30 <<<"$2" >&2
  exit 2
}

case $file in
  *.go)
    command -v gofmt >/dev/null 2>&1 || exit 0
    out=$(gofmt -w "$file" 2>&1) || fail gofmt "$out"
    if [[ -f $project_dir/api/go.mod ]] && command -v go >/dev/null 2>&1; then
      out=$(cd "$(dirname "$file")" && go vet . 2>&1) || fail "go vet" "$out"
    fi
    ;;
  *.ts | *.tsx | *.js | *.jsx | *.css | *.json)
    case $rel in
      web/* | e2e/*) ;;
      *) exit 0 ;;
    esac
    prettier=$project_dir/${rel%%/*}/node_modules/.bin/prettier
    [[ -x $prettier ]] || exit 0
    out=$("$prettier" --write "$file" 2>&1) || fail prettier "$out"
    ;;
  *.tf)
    command -v terraform >/dev/null 2>&1 || exit 0
    out=$(terraform fmt "$file" 2>&1) || fail "terraform fmt" "$out"
    ;;
esac

exit 0
