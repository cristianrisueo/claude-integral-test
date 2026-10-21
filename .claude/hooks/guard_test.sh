#!/usr/bin/env bash
# Tests for guard.sh. Builds a throwaway git repository under $TMPDIR, pipes
# one payload per case into the guard and asserts its exit code (0 allow,
# 2 block). Never touches the real repository.
set -uo pipefail

guard="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/guard.sh"
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

repo=$(mktemp -d "${TMPDIR:-/tmp}/guard-test.XXXXXX")
trap 'rm -rf "$repo"' EXIT

g() { git -C "$repo" -c core.hooksPath=/dev/null -c commit.gpgsign=false "$@"; }

g init -q
g symbolic-ref HEAD refs/heads/main
g config user.email guard-test@example.com
g config user.name guard-test
mkdir -p "$repo/openspec/changes/demo/specs/users" "$repo/api/migrations"
for f in proposal design tasks; do echo "# $f" >"$repo/openspec/changes/demo/$f.md"; done
echo "# Users" >"$repo/openspec/changes/demo/specs/users/spec.md"
echo "CREATE TABLE users ();" >"$repo/api/migrations/000001_init.up.sql"
g add -A
g commit -q -m init
g branch feat/demo-01
g branch propose/demo

pass=0
fail=0

# run <G-row> <block|allow> <branch> <label> <payload>
run() {
  local row=$1 want=$2 branch=$3 label=$4 payload=$5 code
  g switch -q "$branch"
  if [[ ${JQ_MISSING:-} == 1 ]]; then
    CLAUDE_PROJECT_DIR=$repo PATH=/nonexistent /bin/bash "$guard" <<<"$payload" >/dev/null 2>&1
  else
    CLAUDE_PROJECT_DIR=$repo bash "$guard" <<<"$payload" >/dev/null 2>&1
  fi
  code=$?
  local expected=0
  [[ $want == block ]] && expected=2
  if [[ $code == "$expected" ]]; then
    pass=$((pass + 1))
    printf 'PASS %s %-5s [%s] %s\n' "$row" "$want" "$branch" "$label"
  else
    fail=$((fail + 1))
    printf 'FAIL %s %-5s [%s] %s (exit %s, want %s)\n' "$row" "$want" "$branch" "$label" "$code" "$expected"
  fi
}

bash_case() { # <G-row> <block|allow> <branch> <command>
  run "$1" "$2" "$3" "$4" "$(jq -nc --arg c "$4" --arg d "$repo" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}')"
}

file_case() { # <G-row> <block|allow> <branch> <tool> <relative path>
  run "$1" "$2" "$3" "$4 $5" "$(jq -nc --arg t "$4" --arg p "$repo/$5" --arg d "$repo" \
    '{tool_name:$t,tool_input:(if $t == "NotebookEdit" then {notebook_path:$p,new_source:"x"} else {file_path:$p,content:"x",old_string:"a",new_string:"b"} end),cwd:$d}')"
}

F=feat/demo-01
P=propose/demo
C=openspec/changes/demo

# G1: Docker volumes
bash_case G1 block main 'docker compose down -v'
bash_case G1 block main 'docker compose -f compose.yml down --volumes'
bash_case G1 block main 'docker-compose down -v --remove-orphans'
bash_case G1 block main 'docker volume rm claude_pgdata'
bash_case G1 block main 'docker volume prune -f'
bash_case G1 block main 'make build && docker compose down -v'
bash_case G1 allow main 'docker compose down'
bash_case G1 allow main 'docker compose up -d --wait'
bash_case G1 allow main 'docker compose down --remove-orphans'

# G2: Terraform apply / destroy
bash_case G2 block main 'terraform apply'
bash_case G2 block main 'terraform -chdir=infra/envs/prod destroy -auto-approve'
bash_case G2 block main 'cd infra && terraform apply tfplan'
bash_case G2 block main 'echo "$(terraform apply -auto-approve)"'
bash_case G2 allow main 'terraform plan -out=tfplan'
bash_case G2 allow main 'terraform fmt -check -recursive'
bash_case G2 allow main 'terraform plan -destroy'

# G3: commits on main
bash_case G3 block main "git commit -m 'feat: x'"
bash_case G3 block main 'git -C . commit -am x'
bash_case G3 block $F 'git switch main && git commit -m x'
bash_case G3 allow $F "git commit -m 'feat(demo): x'"
bash_case G3 allow $P "git commit -m 'docs(demo): propose demo'"

# G4: pushes to main and force pushes
bash_case G4 block $F 'git push origin main'
bash_case G4 block $F 'git push origin HEAD:main'
bash_case G4 block $F 'git push origin feat/demo-01:refs/heads/main'
bash_case G4 block $F 'git push --force origin feat/demo-01'
bash_case G4 block $F 'git push -f'
bash_case G4 block $F 'git push --force-with-lease origin feat/demo-01'
bash_case G4 block $F 'git push origin +feat/demo-01'
bash_case G4 block main 'git push'
bash_case G4 block main 'git push -u origin HEAD'
bash_case G4 allow $F 'git push -u origin feat/x-01'
bash_case G4 allow $F 'git push origin feat/demo-01'
bash_case G4 allow $P 'git push -u origin propose/demo'

# G5: approved change files on feat/* branches
file_case G5 block $F Edit $C/proposal.md
file_case G5 block $F Write $C/specs/users/spec.md
file_case G5 block $F Write $C/design.md
bash_case G5 block $F "rm $C/tasks.md"
bash_case G5 block $F "rm -rf $C"
bash_case G5 block $F "rm -rf openspec/changes/*"
bash_case G5 block $F "echo x > $C/design.md"
bash_case G5 block $F "echo x >> $C/design.md"
bash_case G5 block $F "sed -i '' 's/a/b/' $C/tasks.md"
bash_case G5 block $F "printf x | tee $C/specs/users/spec.md"
bash_case G5 block $F "truncate -s 0 $C/proposal.md"
bash_case G5 block $F "cp /tmp/x $C/proposal.md"
bash_case G5 block $F "mv $C/design.md /tmp/design.md"
bash_case G5 block $F "git rm $C/proposal.md"
bash_case G5 block $F "mv $C openspec/changes/archive/2026-10-21-demo"
bash_case G5 block $F "git mv $C/specs openspec/changes/archive/2026-10-21-demo"
file_case G5 allow $F Write $C/reports/slice-01.md
file_case G5 allow $F Write openspec/changes/archive/2026-10-21-demo/reports/slice-02.md
bash_case G5 allow $F "echo x > $C/reports/slice-01.md"
bash_case G5 allow $F "git mv $C openspec/changes/archive/2026-10-21-demo"
bash_case G5 allow $F "cat $C/proposal.md"
bash_case G5 allow $F "cp $C/proposal.md /tmp/proposal.md"
file_case G5 allow $P Edit $C/proposal.md
bash_case G5 allow $P "echo x >> $C/tasks.md"

# G6: migrations that already exist on main
file_case G6 block $F Edit api/migrations/000001_init.up.sql
file_case G6 block $P Write api/migrations/000001_init.up.sql
bash_case G6 block $F 'rm api/migrations/000001_init.up.sql'
bash_case G6 block $F "echo 'DROP TABLE users;' >> api/migrations/000001_init.up.sql"
bash_case G6 block $F 'rm -rf api/migrations'
file_case G6 allow $F Write api/migrations/000002_users.up.sql
bash_case G6 allow $F 'cat api/migrations/000001_init.up.sql'
bash_case G6 allow $F "echo 'CREATE INDEX x;' > api/migrations/000002_index.up.sql"

# G7: fail closed
run G7 block $F 'Edit without file_path' '{"tool_name":"Edit","tool_input":{"old_string":"a","new_string":"b"}}'
run G7 block $F 'NotebookEdit without notebook_path' '{"tool_name":"NotebookEdit","tool_input":{"new_source":"x"}}'
run G7 block $F 'payload that is not JSON' 'not json'
JQ_MISSING=1 run G7 block $F 'jq missing (Write README.md)' "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$repo/README.md\"}}"
JQ_MISSING=1 run G7 block $F 'jq missing (Bash ls)' '{"tool_name":"Bash","tool_input":{"command":"ls"}}'
file_case G7 allow $F Write README.md
file_case G7 allow $F NotebookEdit notebooks/explore.ipynb
bash_case G7 allow $F 'ls -la'

printf '\nguard_test.sh: %d passed, %d failed\n' "$pass" "$fail"
((fail == 0))
