#!/usr/bin/env bash
# CI twin of guard.sh rule G5, outside the agent's reach. On a feat/* branch it
# fails if the diff against <base-ref> modifies or deletes an approved change
# file (proposal.md, design.md, tasks.md, specs/** of openspec/changes/<id>/).
# Allowed: pure renames (R100) of a whole change folder into
# openspec/changes/archive/<YYYY-MM-DD>-<id>/, and anything under reports/.
# propose/* and other branches are not checked.
#
# Usage: tools/change-guard.sh <base-ref>    e.g. tools/change-guard.sh origin/main
set -uo pipefail

base=${1:?usage: change-guard.sh <base-ref>}
branch=${GITHUB_HEAD_REF:-$(git branch --show-current 2>/dev/null)}
if [[ $branch != feat/* ]]; then
  echo "change-guard: branch '${branch:-(detached)}' is not feat/*, nothing to check"
  exit 0
fi

if ! diff=$(git diff --name-status --find-renames "$base"...HEAD); then
  echo "change-guard: git diff against '$base' failed (is the history fetched? use fetch-depth: 0)" >&2
  exit 2
fi

approved='^openspec/changes/(archive/[^/]+|[^/.][^/]*)/(proposal\.md|design\.md|tasks\.md|specs/.+)$'
is_approved() { printf '%s\n' "$1" | grep -Eq "$approved"; }

# The change folder a path belongs to: openspec/changes/<id> or openspec/changes/archive/<dir>.
change_dir() { printf '%s\n' "$1" | sed -E 's#^(openspec/changes/(archive/)?[^/]+)/.*#\1#'; }

violations=()
while IFS=$'\t' read -r status src dst; do
  [[ -n $status ]] || continue
  case $status in
    R100)
      is_approved "$src" || is_approved "$dst" || continue
      id=${src#openspec/changes/}
      id=${id%%/*}
      rest=${src#openspec/changes/"$id"/}
      if [[ $id != archive ]] &&
        printf '%s\n' "$dst" | grep -Eq "^openspec/changes/archive/[0-9]{4}-[0-9]{2}-[0-9]{2}-$id/" &&
        [[ ${dst#openspec/changes/archive/*-"$id"/} == "$rest" ]]; then
        continue
      fi
      violations+=("$status $src -> $dst: approved change files only move as a whole folder into openspec/changes/archive/<YYYY-MM-DD>-<id>/")
      ;;
    R* | C*)
      if is_approved "$src" || is_approved "$dst"; then
        violations+=("$status $src -> $dst: approved change files are immutable (a rename with edits is a modification)")
      fi
      ;;
    A*)
      # Adding to a change that already exists on the base modifies it.
      if is_approved "$src" && git cat-file -e "$base:$(change_dir "$src")" 2>/dev/null; then
        violations+=("$status $src: adds to an approved change; a design change is a new change (/propose)")
      fi
      ;;
    *)
      if is_approved "$src"; then
        violations+=("$status $src: approved change files are immutable once merged")
      fi
      ;;
  esac
done <<<"$diff"

if ((${#violations[@]} > 0)); then
  echo "change-guard: branch '$branch' touches approved change files:" >&2
  printf '  %s\n' "${violations[@]}" >&2
  echo "Only openspec/changes/<id>/reports/ may change on feat/* branches." >&2
  exit 1
fi
echo "change-guard: ok ($branch against $base)"
