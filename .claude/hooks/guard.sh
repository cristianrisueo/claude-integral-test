#!/usr/bin/env bash
# PreToolUse guard (Bash|Edit|Write|NotebookEdit). Blocks what must never be
# left to the model, whatever the permission rules say: exit 0 allows, exit 2
# blocks and stderr goes to Claude. Rules G1-G7 are listed in guard_test.sh.
set -uo pipefail

block() {
  printf 'BLOCKED by .claude/hooks/guard.sh [%s]\n%s\n' "$1" "$2" >&2
  printf 'This block is final: adapt, or stop and report. Do not look for another way to do the same thing.\n' >&2
  exit 2
}

# G7: without jq the payload cannot be read, so every call is blocked.
if ! command -v jq >/dev/null 2>&1; then
  block G7 "jq is not installed, so the guard cannot read the tool call. Every call is blocked until jq is on the PATH. Ask Cristian to install jq."
fi

payload=$(cat)
project_dir=${CLAUDE_PROJECT_DIR:-$(pwd)}
tool=$(jq -r '.tool_name // ""' <<<"$payload" 2>/dev/null)
cwd=$(jq -r '.cwd // ""' <<<"$payload" 2>/dev/null)
[[ -n $cwd ]] || cwd=$project_dir

current_branch=$(git -C "$project_dir" branch --show-current 2>/dev/null || true)
branch=$current_branch

main_ref=""
if git -C "$project_dir" rev-parse --verify -q refs/heads/main >/dev/null 2>&1; then
  main_ref=main
elif git -C "$project_dir" rev-parse --verify -q refs/remotes/origin/main >/dev/null 2>&1; then
  main_ref=origin/main
fi

matches() { printf '%s\n' "$1" | grep -Eq "$2"; }

# Lexically resolves . and .. without touching the filesystem.
normalize() {
  local p=$1 lead="" part parts out=()
  [[ $p == /* ]] && lead=/
  IFS=/ read -r -a parts <<<"$p"
  for part in ${parts[@]+"${parts[@]}"}; do
    case $part in
      '' | .) ;;
      ..) if ((${#out[@]} > 0)); then unset "out[$((${#out[@]} - 1))]"; fi ;;
      *) out+=("$part") ;;
    esac
  done
  local IFS=/
  printf '%s%s' "$lead" "${out[*]-}"
}

# Path relative to the project; paths outside it stay absolute.
rel_path() {
  local p=$1
  p=${p//\"/}
  p=${p//\'/}
  [[ -n $p ]] || return 0
  [[ $p == /* ]] || p=$cwd/$p
  p=$(normalize "$p")
  local root
  root=$(normalize "$project_dir")
  if [[ $p == "$root" ]]; then
    p=.
  elif [[ $p == "$root"/* ]]; then
    p=${p#"$root"/}
  fi
  printf '%s' "$p"
}

# G5 and G6: checks one path that is about to be written, moved or deleted.
check_path() {
  local p
  p=$(rel_path "$1")
  [[ -n $p ]] || return 0

  if [[ $branch == feat/* ]]; then
    local approved='(^|/)openspec/changes/(archive/[^/]+|[^/.][^/]*)(/(proposal\.md|design\.md|tasks\.md|specs(/.*)?))?$'
    local globbed='(^|/)openspec/changes/.*[*?[]'
    if matches "$p" "$approved" || { matches "$p" "$globbed" && ! matches "$p" '/reports(/|$)'; }; then
      block G5 "Writing, moving or deleting '$p' on branch '$branch'. The approved files of a change (proposal.md, design.md, tasks.md, specs/**) are immutable once merged.
Allowed: write the slice report under openspec/changes/<id>/reports/. Archive the last slice with
  git mv openspec/changes/<id> openspec/changes/archive/<YYYY-MM-DD>-<id>
A design change is a new change (/propose)."
    fi
  fi

  if [[ -n $main_ref ]] && matches "$p" '(^|/)api/migrations(/.*)?$'; then
    local m
    m=$(printf '%s\n' "$p" | grep -oE 'api/migrations(/.*)?$' | head -n 1)
    if git -C "$project_dir" cat-file -e "$main_ref:$m" 2>/dev/null; then
      block G6 "Writing, moving or deleting '$m', which already exists on $main_ref. Merged migrations are immutable.
Allowed: create a new migration file with the next number."
    fi
  fi
}

# Arguments that are not options (do not start with '-').
operands() {
  local w
  for w in "$@"; do
    [[ $w == -* ]] || printf '%s\n' "$w"
  done
}

check_paths_of() {
  local t
  while IFS= read -r t; do
    check_path "$t"
  done < <(operands "$@")
}

check_docker() {
  local s=" $* "
  if matches "$s" ' volume( [^ ]+)* (rm|prune)( |$)'; then
    block G1 "'$*' deletes Docker volumes, which hold the database data.
Allowed: 'docker compose down' (or 'make down') without -v/--volumes. Deleting data is Cristian's call, by hand."
  fi
  if matches "$s" ' down( |$)' && matches "$s" ' (-v|--volumes(=[^ ]*)?|-[A-Za-z]*v[A-Za-z]*)( |$)'; then
    block G1 "'$*' deletes the stack's Docker volumes (-v/--volumes), which hold the database data.
Allowed: 'docker compose down' (or 'make down') without -v/--volumes."
  fi
}

check_terraform() {
  local w
  for w in "$@"; do
    [[ $w == -* ]] && continue
    case $w in
      apply | destroy)
        block G2 "'terraform $w' never runs locally.
Allowed: 'terraform plan' / 'terraform fmt' / 'terraform validate'. Infrastructure changes are applied by CD after Cristian approves them in GitHub."
        ;;
    esac
    return 0
  done
}

check_git() {
  local args=("$@") i=0 sub=""
  while ((i < ${#args[@]})); do
    case ${args[i]} in
      -C | -c | --git-dir | --work-tree | --namespace) i=$((i + 2)) ;;
      -*) i=$((i + 1)) ;;
      *)
        sub=${args[i]}
        i=$((i + 1))
        break
        ;;
    esac
  done
  local rest=()
  ((i < ${#args[@]})) && rest=("${args[@]:i}")

  case $sub in
    switch | checkout)
      # Track the branch a compound command moves to (git switch main && git commit).
      local w
      for w in ${rest[@]+"${rest[@]}"}; do
        [[ $w == -* || $w == -- ]] && continue
        branch=$w
        break
      done
      ;;
    commit)
      if [[ $branch == main ]]; then
        block G3 "'git commit' on main. main only changes through squash-merged PRs.
Allowed: create a branch first (git switch -c feat/<id>-<NN> or propose/<id>), then commit."
      fi
      ;;
    push)
      local w refspecs=()
      for w in ${rest[@]+"${rest[@]}"}; do
        case $w in
          --force | --force-with-lease | --force-with-lease=* | --force-if-includes | --mirror | --all | --delete | -d | --prune)
            block G4 "'git push $w' rewrites or deletes remote history.
Allowed: git push -u origin feat/<id>-<NN> (or propose/<id>), then merge through the PR with /ship."
            ;;
          --*) ;;
          -*)
            if matches "$w" '^-[A-Za-z]*[fd][A-Za-z]*$'; then
              block G4 "'git push $w' force-pushes or deletes a remote branch.
Allowed: git push -u origin feat/<id>-<NN> (or propose/<id>)."
            fi
            ;;
          *) refspecs+=("$w") ;;
        esac
      done
      local n=${#refspecs[@]} j
      for ((j = 1; j < n; j++)); do
        w=${refspecs[j]}
        if [[ $w == +* ]]; then
          block G4 "'$w' is a force refspec.
Allowed: git push -u origin feat/<id>-<NN> (or propose/<id>)."
        fi
        if matches "$w" '^(.*:)?(refs/heads/)?main$' || { [[ $branch == main ]] && matches "$w" '^(HEAD|@)$'; }; then
          block G4 "'git push ... $w' targets main. main only changes through squash-merged PRs.
Allowed: git push -u origin feat/<id>-<NN> (or propose/<id>), then /ship."
        fi
      done
      if ((n <= 1)) && [[ $branch == main ]]; then
        block G4 "'git push' from main pushes main. main only changes through squash-merged PRs.
Allowed: switch to your branch and git push -u origin feat/<id>-<NN> (or propose/<id>)."
      fi
      ;;
    rm)
      check_paths_of ${rest[@]+"${rest[@]}"}
      ;;
    mv)
      local ops=() t
      while IFS= read -r t; do ops+=("$(rel_path "$t")"); done < <(operands ${rest[@]+"${rest[@]}"})
      # The one allowed move: a whole change folder into the archive.
      if ((${#ops[@]} == 2)) && matches "${ops[0]}" '^openspec/changes/[^/.][^/]*$' && [[ ${ops[0]} != openspec/changes/archive ]]; then
        local id=${ops[0]##*/}
        if matches "${ops[1]}" "^openspec/changes/archive/[0-9]{4}-[0-9]{2}-[0-9]{2}-$id\$"; then
          return 0
        fi
      fi
      for t in ${ops[@]+"${ops[@]}"}; do check_path "$t"; done
      ;;
  esac
}

check_segment() {
  local words=() i=0 w prog
  read -r -a words <<<"$1"
  # Skip leading variable assignments and wrappers that run their argument.
  while ((i < ${#words[@]})); do
    w=${words[i]}
    case $w in
      [A-Za-z_]*=*) i=$((i + 1)) ;;
      sudo | command | builtin | exec | nohup | time | nice | noglob | env | xargs | then | do | else | if | while | until | '!' | '{' | '(') i=$((i + 1)) ;;
      timeout) i=$((i + 2)) ;;
      *) break ;;
    esac
  done
  ((i < ${#words[@]})) || return 0
  words=("${words[@]:i}")
  prog=${words[0]//\"/}
  prog=${prog//\'/}
  prog=${prog##*/}
  local args=()
  ((${#words[@]} > 1)) && args=("${words[@]:1}")

  case $prog in
    docker | docker-compose) check_docker "${words[@]}" ;;
    terraform) check_terraform ${args[@]+"${args[@]}"} ;;
    git) check_git ${args[@]+"${args[@]}"} ;;
    rm | rmdir | truncate | tee | mv | unlink | shred) check_paths_of ${args[@]+"${args[@]}"} ;;
    cp | install)
      local last=""
      while IFS= read -r w; do last=$w; done < <(operands ${args[@]+"${args[@]}"})
      check_path "$last"
      ;;
    sed | gsed)
      for w in ${args[@]+"${args[@]}"}; do
        if matches "$w" '^(-[A-Za-z]*i|--in-place)'; then
          check_paths_of ${args[@]+"${args[@]}"}
          break
        fi
      done
      ;;
  esac
}

# Heredoc bodies are data (PR bodies, comments), not commands, so they are
# dropped before the checks, unless a shell reads them (bash <<EOF).
# Here-strings (<<<) are not heredocs and are left alone.
strip_heredocs() {
  local line term="" dash="" keep=0 spec cmp
  while IFS= read -r line || [[ -n $line ]]; do
    if [[ -n $term ]]; then
      cmp=$line
      [[ -n $dash ]] && cmp=${cmp#"${cmp%%[!$'\t']*}"}
      if [[ $cmp == "$term" ]]; then
        term=""
      elif ((keep)); then
        printf '%s\n' "$line"
      fi
      continue
    fi
    printf '%s\n' "$line"
    spec=$(printf '%s\n' "$line" | sed -nE "s/(^|.*[^<])<<(-?)[[:space:]]*['\"]?([A-Za-z_][A-Za-z0-9_]*)['\"]?.*/\2 \3/p")
    if [[ -n $spec ]]; then
      dash=${spec% *}
      term=${spec#* }
      keep=0
      matches "${line%%<<*}" '(^|[^[:alnum:]_.-])(ba|z|da|k)?sh[[:space:]]*$|(^|[^[:alnum:]_.-])(ba|z|da|k)?sh[[:space:]]+(-[a-z]+[[:space:]]*)*$' && keep=1
    fi
  done <<<"$1"
}

check_bash() {
  local cmd seg t
  cmd=$(strip_heredocs "$1")
  # Pass 1 splits on ; & | and newlines. Pass 2 also splits on ( ) and
  # backticks to reach commands inside subshells and substitutions.
  for pass in ';&|' ';&|()`'; do
    branch=$current_branch
    while IFS= read -r seg; do
      check_segment "$seg"
    done < <(printf '%s\n' "$cmd" | tr "$pass" '\n\n\n\n\n\n')
  done
  branch=$current_branch
  # Redirections: > file and >> file (not >&2 or 2>&1).
  while IFS= read -r t; do
    t=${t#>}
    t=${t#>}
    t=${t#"${t%%[![:space:]]*}"}
    check_path "$t"
  done < <(printf '%s\n' "$cmd" | grep -oE '>>?[[:space:]]*[^[:space:]&|;<>()]+' || true)
}

case $tool in
  Bash)
    check_bash "$(jq -r '.tool_input.command // ""' <<<"$payload")"
    ;;
  *)
    path=$(jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' <<<"$payload" 2>/dev/null)
    if [[ -z $path ]]; then
      block G7 "The ${tool:-unknown} call has neither file_path nor notebook_path, so the guard cannot check what it writes (fail closed).
Allowed: call the tool with an explicit file_path (Edit/Write) or notebook_path (NotebookEdit)."
    fi
    check_path "$path"
    ;;
esac

exit 0
