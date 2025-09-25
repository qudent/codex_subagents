#!/usr/bin/env bash
# Dual-use script: compatible with bash and zsh (emulates POSIX sh semantics when run under zsh).
# Provides interactive Codex agent helpers with worktree + tmux management.

# shellcheck disable=SC2312,SC1090

if [ -n "${ZSH_VERSION-}" ]; then
  emulate -L sh 2>/dev/null || true
fi

if [ -n "${BASH_SOURCE-}" ]; then
  __AGENT_SELF=${BASH_SOURCE[0]}
elif [ -n "${ZSH_VERSION-}" ]; then
  __AGENT_SELF=${(%):-%N}
else
  __AGENT_SELF=$0
fi

set -o errexit
set -o pipefail
IFS=$' \t\n'

__agent_script_dir(){
  cd "$(dirname "$__AGENT_SELF")" 2>/dev/null && pwd
}

SCRIPT_DIR="$(__agent_script_dir)"
DEFAULT_CONF="$SCRIPT_DIR/agent.conf"
DEFAULT_WHITELIST="OPENAI_API_KEY ANTHROPIC_API_KEY OPENAI_BASE_URL PATH"
DEFAULT_MAC_ATTACH=1
DEFAULT_ENV_MODE="auto"
DEFAULT_PIPE_LOG=0

# Load user overrides if present.
if [ -f "$DEFAULT_CONF" ]; then
  set +u
  . "$DEFAULT_CONF"
  set -u 2>/dev/null || true
fi

__agent_usage(){
  cat <<'USAGE'
Usage: agent.sh <command> [options]

Commands:
  spawn        Spawn a new interactive Codex tmux session + worktree
  list         List active Codex tmux sessions
  attach       Attach to a session by task id
  status       Display metadata for a task id
  reload-env   Reload environment inside a session
  cleanup      Terminate session, remove worktree + branch

Run "agent.sh <command> --help" for detailed options.
USAGE
}

__agent_require(){
  command -v "$1" >/dev/null 2>&1 || {
    printf 'Error: %s is required.\n' "$1" >&2
    exit 1
  }
}

__agent_now(){ date +%Y%m%d-%H%M%S; }

__agent_random_suffix(){ printf '%04x' "$((RANDOM & 0xffff))"; }

__agent_git_root(){
  git rev-parse --show-toplevel 2>/dev/null || {
    printf 'Error: not inside a git repository.\n' >&2
    exit 1
  }
}

__agent_git_clean(){
  git status --porcelain --untracked-files=normal 2>/dev/null | grep -q '.' && return 1
  return 0
}

__agent_task_id(){
  local ts rand
  ts="$(__agent_now)"
  rand="$(__agent_random_suffix)"
  printf '%s-%s' "$ts" "$rand"
}

__agent_branch_name(){ printf 'task/%s' "$1"; }

__agent_session_name(){ printf 'codex-%s' "$1"; }

__agent_worktree_path(){ printf '%s/.worktrees/%s' "$1" "$2"; }

__agent_detect_os(){
  case "$(uname -s 2>/dev/null)" in
    Darwin) printf 'mac';;
    Linux) printf 'linux';;
    *) printf 'other';;
  esac
}

__agent_print_spawn_help(){
  cat <<'SPAWN_HELP'
Usage: agent.sh spawn [options] "Task description / initial prompt"

Options:
  --force           Allow spawning when git status is dirty
  --no-window       Skip launching Terminal/iTerm window (print attach hint)
  --env <mode>      Override env mode: auto|direnv|whitelist
  --log             Pipe tmux pane output to .codex.log in worktree
  --help            Show this help message
SPAWN_HELP
}

__agent_print_cleanup_help(){
  cat <<'CLEAN_HELP'
Usage: agent.sh cleanup <task-id> [--force]
  Removes tmux session, git worktree, and deletes the task branch.

Options:
  --force    Force git worktree removal even if dirty/unmerged
CLEAN_HELP
}

__agent_print_reload_help(){
  cat <<'RELOAD_HELP'
Usage: agent.sh reload-env <task-id>
  Re-applies environment for the given session (direnv reload or whitelist export).
RELOAD_HELP
}

__agent_print_attach_help(){
  cat <<'ATTACH_HELP'
Usage: agent.sh attach <task-id>
  Attach your terminal to the tmux session codex-<task-id>.
ATTACH_HELP
}

__agent_print_status_help(){
  cat <<'STATUS_HELP'
Usage: agent.sh status <task-id>
  Print branch, worktree path, and tmux session info for task.
STATUS_HELP
}

__agent_list(){
  __agent_require tmux
  tmux ls 2>/dev/null | grep '^codex-' || printf 'No codex sessions found.\n'
}

__agent_attach(){
  [ -n "$1" ] || { __agent_print_attach_help >&2; exit 1; }
  __agent_require tmux
  tmux attach -t "$(__agent_session_name "$1")"
}

__agent_status(){
  [ -n "$1" ] || { __agent_print_status_help >&2; exit 1; }
  __agent_require git
  local root branch worktree session
  root="$(__agent_git_root)"
  worktree="$(__agent_worktree_path "$root" "$1")"
  branch="$(__agent_branch_name "$1")"
  session="$(__agent_session_name "$1")"

  if [ ! -d "$worktree" ]; then
    printf 'Worktree missing: %s\n' "$worktree"
  else
    printf 'Worktree: %s\n' "$worktree"
  fi
  if git show-ref --verify --quiet "refs/heads/$branch"; then
    printf 'Branch:   %s\n' "$branch"
  else
    printf 'Branch:   %s (missing)\n' "$branch"
  fi
  if tmux has-session -t "$session" 2>/dev/null; then
    printf 'Session:  %s (active)\n' "$session"
  else
    printf 'Session:  %s (not running)\n' "$session"
  fi
}

__agent_env_whitelist(){
  if [ -n "${AGENT_ENV_WHITELIST-}" ]; then
    printf '%s\n' $AGENT_ENV_WHITELIST
    return
  fi
  local manifest="${AGENT_ENV_FILE:-$SCRIPT_DIR/agent.env.example}"
  if [ -f "$manifest" ]; then
    awk -F= 'BEGIN{IGNORECASE=0} {gsub(/#.*/,"",$1); gsub(/[[:space:]]/,"",$1); if(length($1)) print $1}' "$manifest"
    return
  fi
  printf '%s\n' $DEFAULT_WHITELIST
}

__agent_render_exports(){
  local var value
  while IFS= read -r var; do
    [ -n "$var" ] || continue
    value=$(eval "printf '%s' \"\${$var-}\"")
    [ -n "$value" ] || continue
    printf 'export %s=%q\n' "$var" "$value"
  done
}

__agent_shell_escape(){
  printf '%q' "$1"
}

__agent_prepare_launch_script(){
  local worktree="$1" prompt="$2" script_path
  script_path="$worktree/.agent-launch.sh"
  umask 077
  {
    printf '#!/usr/bin/env bash\n'
    printf 'set -euo pipefail\n'
    printf 'cd %q\n' "$worktree"
    __agent_env_whitelist | __agent_render_exports
    printf 'exec codex %q\n' "$prompt"
  } > "$script_path"
  chmod 0700 "$script_path"
  printf '%s' "$script_path"
}

__agent_setup_direnv(){
  local worktree="$1" envrc
  envrc="$worktree/.envrc"
  if [ ! -f "$envrc" ]; then
    umask 077
    cat <<'ENVRC' > "$envrc"
ROOT="$(git rev-parse --show-toplevel)"
dotenv "$ROOT/.env"
ENVRC
  fi
  ( cd "$worktree" && direnv allow >/dev/null 2>&1 ) || true
}

__agent_spawn(){
  local force=0 no_window=0 env_mode="${AGENT_ENV_MODE:-$DEFAULT_ENV_MODE}" pipe_log="${AGENT_PIPE_LOG:-$DEFAULT_PIPE_LOG}" prompt
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --force) force=1; shift ;;
      --no-window) no_window=1; shift ;;
      --env)
        [ -n "${2-}" ] || { printf 'Error: --env requires mode.\n' >&2; exit 1; }
        env_mode="$2"; shift 2 ;;
      --log) pipe_log=1; shift ;;
      --help) __agent_print_spawn_help; exit 0 ;;
      --*) printf 'Unknown option: %s\n' "$1" >&2; exit 1 ;;
      *) break ;;
    esac
  done

  prompt="$*"
  [ -n "$prompt" ] || { printf 'Error: task prompt required.\n' >&2; exit 1; }

  __agent_require tmux
  __agent_require codex
  __agent_require git

  local root
  root="$(__agent_git_root)"
  mkdir -p "$root/.worktrees"

  if [ "$force" -ne 1 ] && ! __agent_git_clean; then
    printf 'Refusing to spawn: git status not clean. Use --force to override.\n' >&2
    exit 1
  fi

  local task_id branch worktree session
  task_id="$(__agent_task_id)"
  branch="$(__agent_branch_name "$task_id")"
  worktree="$(__agent_worktree_path "$root" "$task_id")"
  session="$(__agent_session_name "$task_id")"

  git worktree add -b "$branch" "$worktree" >/dev/null

  # Reuse dependency caches by symlinking common directories into the worktree.
  for cache in node_modules .venv venv vendor; do
    if [ -d "$root/$cache" ] && [ ! -e "$worktree/$cache" ]; then
      ln -s "$root/$cache" "$worktree/$cache"
    fi
  done

  local agents="$worktree/AGENTS.md"
  [ -f "$agents" ] || : > "$agents"
  local now_iso
  now_iso="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  local prev_branch
  prev_branch="$(git rev-parse --abbrev-ref HEAD)"

  cat >> "$agents" <<EOF_TASK

## Task $branch
- Created: $now_iso
- Parent branch: $prev_branch
- Status: pending
- Description:
$prompt

- Agent contract:
  1) Work ONLY in this worktree/branch: \`$branch\`.\
  2) Keep THIS section’s **Status** updated (pending → working → success/failed/confused + short note).\
  3) On success: **commit with message exactly**: \`task $branch finished\`.\
  4) Then merge into \`$prev_branch\` (fast-forward or leave PR instructions).\
  5) On failure/confusion: set Status accordingly and **ask the user** with concrete questions; do NOT merge.\
  6) Small, reversible commits; tests/docs if applicable.\
  7) For Python work: activate \`.venv\` (source \`.venv/bin/activate\`) and install via \`uv pip\`.\
EOF_TASK

  ( cd "$worktree" && git add AGENTS.md && git commit -m "chore(agent): register $branch task" >/dev/null 2>&1 || true )


  local os mode
  os="$(__agent_detect_os)"

  case "$env_mode" in
    auto)
      if command -v direnv >/dev/null 2>&1; then
        mode="direnv"
      else
        mode="whitelist"
      fi
      ;;
    direnv|whitelist)
      mode="$env_mode"
      ;;
    *) printf 'Error: unknown env mode %s\n' "$env_mode" >&2; exit 1 ;;
  esac

  local launch_cmd launch_script
  if [ "$mode" = "direnv" ]; then
    __agent_require direnv
    __agent_setup_direnv "$worktree"
    launch_cmd="cd $(__agent_shell_escape "$worktree") && direnv exec $(__agent_shell_escape "$worktree") codex $(__agent_shell_escape "$prompt")"
  else
    launch_script="$(__agent_prepare_launch_script "$worktree" "$prompt")"
    launch_cmd="$(__agent_shell_escape "$launch_script")"
  fi

  tmux new-session -d -s "$session" "$launch_cmd"

  if [ "$pipe_log" -eq 1 ]; then
    tmux pipe-pane -t "$session" -o "cat >> '$worktree/.codex.log'" >/dev/null 2>&1 || true
  fi

  if [ "$no_window" -ne 1 ]; then
    if [ "$os" = "mac" ] && [ "${AGENT_MAC_ATTACH:-$DEFAULT_MAC_ATTACH}" -eq 1 ]; then
      local attach_cmd
      attach_cmd="tmux attach -t $session"
      /usr/bin/osascript >/dev/null <<OSA || printf 'Warning: could not open macOS Terminal. Attach manually.\n'
tell application "Terminal"
  do script "$attach_cmd"
end tell
OSA
    else
      printf 'Attach with: tmux attach -t %s\n' "$session"
    fi
  else
    printf 'Attach with: tmux attach -t %s\n' "$session"
  fi

  printf 'Spawned task %s\nWorktree: %s\nSession:  %s\n' "$task_id" "$worktree" "$session"
}

__agent_reload_env(){
  [ -n "$1" ] || { __agent_print_reload_help >&2; exit 1; }
  __agent_require tmux
  local session
  session="$(__agent_session_name "$1")"
  if ! tmux has-session -t "$session" 2>/dev/null; then
    printf 'No tmux session for %s\n' "$1" >&2
    exit 1
  fi

  if command -v direnv >/dev/null 2>&1; then
    tmux send-keys -t "$session" 'direnv reload' C-m
  else
    local exports
    exports=$( __agent_env_whitelist | __agent_render_exports )
    [ -n "$exports" ] || return 0
    while IFS= read -r line; do
      tmux send-keys -t "$session" "$line" C-m
    done <<EXPORTS
$exports
EXPORTS
  fi
}

__agent_cleanup(){
  local task_id="$1" force_flag=0
  shift
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --force) force_flag=1; shift ;;
      --help) __agent_print_cleanup_help; exit 0 ;;
      --*) printf 'Unknown option: %s\n' "$1" >&2; exit 1 ;;
      *) printf 'Unexpected argument: %s\n' "$1" >&2; exit 1 ;;
    esac
  done
  [ -n "$task_id" ] || { __agent_print_cleanup_help >&2; exit 1; }
  __agent_require tmux
  __agent_require git

  local root worktree branch session
  root="$(__agent_git_root)"
  worktree="$(__agent_worktree_path "$root" "$task_id")"
  branch="$(__agent_branch_name "$task_id")"
  session="$(__agent_session_name "$task_id")"

  tmux kill-session -t "$session" 2>/dev/null || true
  if [ "$force_flag" -eq 1 ]; then
    git worktree remove -f "$worktree" 2>/dev/null || true
  else
    git worktree remove "$worktree" 2>/dev/null || true
  fi
  git branch -D "$branch" 2>/dev/null || true
  printf 'Cleanup complete for %s\n' "$task_id"
}

# Public wrappers (available when the script is sourced).
agent_spawn_i(){ __agent_spawn "$@"; }
agent_list(){ __agent_list "$@"; }
agent_attach(){ __agent_attach "$@"; }
agent_status(){ __agent_status "$@"; }
agent_reload_env(){ __agent_reload_env "$@"; }
agent_cleanup(){ __agent_cleanup "$@"; }

main(){
  [ "$#" -gt 0 ] || { __agent_usage; exit 1; }
  case "$1" in
    spawn) shift; __agent_spawn "$@" ;;
    list) __agent_list ;;
    attach) shift; __agent_attach "$@" ;;
    status) shift; __agent_status "$@" ;;
    reload-env) shift; __agent_reload_env "$@" ;;
    cleanup)
      shift
      __agent_cleanup "$@"
      ;;
    --help|-h) __agent_usage ;;
    *) printf 'Unknown command: %s\n' "$1" >&2; __agent_usage >&2; exit 1 ;;
  esac
}

if [ "$__AGENT_SELF" = "$0" ]; then
  main "$@"
fi
