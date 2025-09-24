#!/usr/bin/env zsh
# Codex subagent helpers sourced by your interactive shell.

# Preserve caller shell options so sourcing this file stays side-effect free.
typeset -A __codex_saved_opts
for __codex_opt in errexit nounset pipefail; do
  if [[ -o $__codex_opt ]]; then
    __codex_saved_opts[$__codex_opt]=1
  else
    __codex_saved_opts[$__codex_opt]=0
  fi
done

set -euo pipefail

_applescript_escape(){ sed 's/\\/\\\\/g; s/"/\\"/g'; }

agent_spawn(){
  setopt localoptions errexit nounset pipefail
  git rev-parse --is-inside-work-tree >/dev/null || { echo "Not in a git repo"; return 1; }
  local desc="${*:-(no description)}"
  local repo_root prev_branch ts rnd slug branch worktree now_iso env_snapshot
  repo_root="$(git rev-parse --show-toplevel)"
  prev_branch="$(git rev-parse --abbrev-ref HEAD)"
  ts="$(date +%Y%m%d-%H%M%S)"
  rnd="$(LC_ALL=C tr -dc 'a-f0-9' </dev/urandom | head -c6)"
  slug="$(printf '%s' "$desc" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9- ' | tr ' ' '-' | sed 's/--*/-/g' | cut -c1-32)"
  [[ -z "$slug" ]] && slug="task"
  branch="agent/${slug}-${ts}-${rnd}"
  worktree="${repo_root}/.worktrees/${branch}"

  mkdir -p "${repo_root}/.worktrees"
  git -C "$repo_root" worktree add -b "$branch" "$worktree" HEAD

  # Reuse dependency caches by symlinking common directories into the worktree.
  for cache in node_modules .venv venv vendor; do
    if [[ -d "$repo_root/$cache" && ! -e "$worktree/$cache" ]]; then
      ln -s "$repo_root/$cache" "$worktree/$cache"
    fi
  done

  local agents="$worktree/AGENTS.md"
  [[ -f "$agents" ]] || : > "$agents"
  now_iso="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  cat >> "$agents" <<EOF_TASK

## Task $branch
- Created: $now_iso
- Parent branch: $prev_branch
- Status: pending
- Description:
$desc

- Agent contract:
  1) Work ONLY in this worktree/branch: \`$branch\`.
  2) Keep THIS section’s **Status** updated (pending → working → success/failed/confused + short note).
  3) On success: **commit with message exactly**: \`task $branch finished\`.
  4) Then merge into \`$prev_branch\` (fast-forward or leave PR instructions).
  5) On failure/confusion: set Status accordingly and **ask the user** with concrete questions; do NOT merge.
  6) Small, reversible commits; tests/docs if applicable.
  7) For Python work: activate \`.venv\` (source \`.venv/bin/activate\`) and install via \`uv pip\`.
EOF_TASK

  ( cd "$worktree" && git add AGENTS.md && git commit -m "chore(agent): register $branch task" >/dev/null )

  env_snapshot="$(mktemp -t codex-agent-env-XXXXXX)"
  export -p > "$env_snapshot"
  chmod 0600 "$env_snapshot"

  local run
  run=$(cat <<EOF_RUN
set -e
cd "$worktree"
if [[ -f "$env_snapshot" ]]; then
  source "$env_snapshot"
  rm -f "$env_snapshot"
fi
if command -v uv >/dev/null 2>&1; then
  export PIP_COMMAND="uv pip"
fi
export CODEX_QUIET_MODE=1
echo "Subagent running for: '$branch' (worktree: \$(pwd))"
while true; do
  codex exec "Continue working on task '$branch'. Follow AGENTS.md contract; update Status; stop only when done or blocked."
  git pull --ff-only >/dev/null 2>&1 || true
  if git log --grep="^task '$branch' finished$" -1 --pretty=format:%H >/dev/null 2>&1; then
    echo "Completion commit detected. Exiting Codex loop."
    break
  fi
  sleep 60
done
EOF_RUN
)

  local run_esc
  run_esc="$(printf '%s' "$run" | _applescript_escape)"
  /usr/bin/osascript >/dev/null <<APPLESCRIPT
tell application "Terminal" to do script "$run_esc"
APPLESCRIPT

  echo "$branch"
}

agent_status(){
  setopt localoptions errexit nounset pipefail
  local branch="${1:-}"
  [[ -n "$branch" ]] || { echo "Usage: agent_status <branch>"; return 1; }
  local repo_root agents
  repo_root="$(git rev-parse --show-toplevel)"
  agents="$repo_root/.worktrees/$branch/AGENTS.md"
  [[ -f "$agents" ]] || { echo "No AGENTS.md for $branch"; return 1; }
  awk -v b="## Task $branch" '
    $0==b {insec=1; next}
    insec && /^## / {exit}
    insec && $1=="-" && $2=="Status:"{print; exit}
  ' "$agents"
}

agent_await(){
  setopt localoptions errexit nounset pipefail
  local branch="${1:-}"
  [[ -n "$branch" ]] || { echo "Usage: agent_await <branch>"; return 1; }
  local repo_root wt agents
  repo_root="$(git rev-parse --show-toplevel)"
  wt="$repo_root/.worktrees/$branch"
  agents="$wt/AGENTS.md"
  [[ -d "$wt/.git" ]] || { echo "No such worktree: $wt"; return 1; }
  local parent
  parent="$(awk -v b="## Task $branch" '$0==b{in=1;next} in&&/^## /{exit} in&&$1=="-"&&$2=="Parent"&&$3=="branch:"{print $4;exit}' "$agents")"
  [[ -n "${parent:-}" ]] || { echo "Parent branch not found"; return 1; }

  echo "⏳ Waiting for 'task $branch finished'… (parent: $parent)"
  while true; do
    (cd "$wt" && git pull --ff-only >/dev/null 2>&1 || true)
    if (cd "$wt" && git log --grep="^task $branch finished$" -1 --pretty=format:%H >/dev/null 2>&1); then
      echo "✅ Completion detected."
      break
    fi
    printf "\r%s | %s" "$(date '+%H:%M:%S')" "$(agent_status "$branch" 2>/dev/null || echo '- Status: unknown')"
    sleep 5
  done

  echo; echo "🔀 Merging $branch → $parent (ff-only)…"
  (
    cd "$repo_root"
    git fetch -q || true
    local cur="$(git rev-parse --abbrev-ref HEAD)"
    trap 'git checkout -q "$cur" || true' EXIT
    git checkout -q "$parent"
    if git merge --ff-only "$branch"; then
      echo "✅ Merged into $parent."
    else
      echo "⚠️ Couldn’t fast-forward. Open a PR or resolve manually."
    fi
  )
  echo "🧹 Cleanup when ready: agent_cleanup $branch"
}

agent_watch_all(){
  setopt localoptions errexit nounset pipefail
  local repo_root
  repo_root="$(git rev-parse --show-toplevel)"
  while true; do
    echo "---- $(date '+%H:%M:%S') ----"
    git worktree list --porcelain | awk "/worktree / && \$2 ~ /\.worktrees\/agent\// {print \$2}" | while read -r wt; do
      local b
      b="${wt#${repo_root}/.worktrees/}"
      (cd "$wt" && git pull --ff-only >/dev/null 2>&1 || true)
      echo "$b  |  $(agent_status "$b" 2>/dev/null || echo '- Status: unknown')"
    done
    sleep 10
  done
}

agent_cleanup(){
  setopt localoptions errexit nounset pipefail
  local branch="${1:-}"
  local flag="${2:-}"
  [[ -n "$branch" ]] || { echo "Usage: agent_cleanup <branch> [--force]"; return 1; }
  local repo_root wt
  repo_root="$(git rev-parse --show-toplevel)"
  wt="$repo_root/.worktrees/$branch"
  local worktree_args=()
  local branch_args=(-d)
  local status=0
  if [[ "$flag" == "--force" ]]; then
    worktree_args+=(--force)
    branch_args=(-D)
  elif [[ -n "$flag" ]]; then
    echo "Unknown flag: $flag" >&2
    return 1
  fi

  if [[ -d "$wt" ]]; then
    if git -C "$repo_root" worktree remove "${worktree_args[@]}" "$wt"; then
      echo "Removed worktree $wt"
    else
      echo "Worktree removal failed. Try agent_cleanup $branch --force" >&2
      status=1
    fi
  else
    echo "No worktree at $wt"
  fi

  if git -C "$repo_root" show-ref --verify --quiet "refs/heads/$branch"; then
    if git -C "$repo_root" branch "${branch_args[@]}" "$branch"; then
      echo "Deleted branch $branch"
    else
      echo "Branch deletion failed. You may need agent_cleanup $branch --force" >&2
      status=1
    fi
  else
    echo "No branch named $branch"
  fi

  return $status
}

for __codex_opt in errexit nounset pipefail; do
  if (( __codex_saved_opts[$__codex_opt] )); then
    set -o $__codex_opt
  else
    set +o $__codex_opt
  fi
done
unset __codex_opt __codex_saved_opts
