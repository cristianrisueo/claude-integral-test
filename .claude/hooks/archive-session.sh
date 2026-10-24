#!/usr/bin/env bash
# SessionEnd hook. Copies the session's transcript (transcript_path) to
# .claude/sessions/<YYYY-MM-DD>-<session-id>.jsonl, which git ignores, for
# /retro to read. A resumed session overwrites its earlier copy. It must
# never fail a session: on any error it writes nothing and exits 0.
set -uo pipefail

archive() {
  command -v jq >/dev/null 2>&1 || return 0
  local payload session transcript cwd project_dir dir dest tmp f
  payload=$(cat)
  session=$(jq -r '.session_id // ""' <<<"$payload") || return 0
  transcript=$(jq -r '.transcript_path // ""' <<<"$payload") || return 0
  cwd=$(jq -r '.cwd // ""' <<<"$payload") || return 0
  # Only [A-Za-z0-9_-], so a crafted id cannot leave the folder.
  session=${session//[^A-Za-z0-9_-]/}
  [[ -n $session && -n $transcript && -f $transcript ]] || return 0

  project_dir=${CLAUDE_PROJECT_DIR:-${cwd:-$(pwd)}}
  dir=$project_dir/.claude/sessions
  mkdir -p "$dir" || return 0

  dest=$dir/$(date +%F)-$session.jsonl
  for f in "$dir"/*-"$session".jsonl; do
    [[ -f $f ]] && dest=$f && break
  done

  # Copy, then rename, so a reader never sees a half-written file.
  tmp=$(mktemp "$dir/.archive.XXXXXX") || return 0
  if cp "$transcript" "$tmp" && mv -f "$tmp" "$dest"; then
    return 0
  fi
  rm -f "$tmp"
}

archive 2>/dev/null || true
exit 0
