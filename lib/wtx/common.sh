# shellcheck shell=bash

need() { command -v "$1" >/dev/null 2>&1; }

wtx::reset_tool_tracking() {
  WTX_TOOL_SUMMARY=""
  WTX_MISSING_TOOLS=""
}

wtx::append_tool_summary() {
  if [ -z "${WTX_TOOL_SUMMARY:-}" ]; then
    WTX_TOOL_SUMMARY="tools: $1"
  else
    WTX_TOOL_SUMMARY="$WTX_TOOL_SUMMARY $1"
  fi
}

wtx::record_missing_tool() {
  if [ -z "${WTX_MISSING_TOOLS:-}" ]; then
    WTX_MISSING_TOOLS="$1"
  else
    WTX_MISSING_TOOLS="$WTX_MISSING_TOOLS $1"
  fi
}

wtx::print_tool_summary() {
  if [ -n "${WTX_TOOL_SUMMARY:-}" ]; then
    printf '%s\n' "$WTX_TOOL_SUMMARY" >&2
  fi
  if [ -n "${WTX_MISSING_TOOLS:-}" ]; then
    printf '[wtx] missing required tools: %s\n' "$WTX_MISSING_TOOLS" >&2
    exit 2
  fi
}

wtx::usage() {
  cat <<'USAGE'
wtx — create/reuse a git worktree and open a socat-managed shell with a one-line banner.

Usage: wtx [NAME] [-c CMD] [--from REF] [--no-open]
            [--dry-run] [--verbose] [--delete-branches] [--no-git-logging]
            [--_post-commit]
Examples:
  wtx                       # auto-name branch wtx/<parent>-NN, create worktree + shell
  wtx feature-xyz -c 'pytest -q'   # send raw keystrokes after session is ready

Flags:
  -c CMD            Send raw keystrokes to the shell (exactly, then Enter)
  --from REF        Use REF as starting point (default: HEAD)
  --no-open         Do not attach/switch to the shell; only print attach command
  --dry-run         Ignored (reserved for wtx-prune)
  --delete-branches Ignored (reserved for wtx-prune)
  --verbose         Print extra diagnostics to stderr
  --no-git-logging  Disable git commit logging for spinup/-c
  --_post-commit    Internal: invoked by git hook to broadcast commit messages
  --help            This help message

Environment:
  WTX_OPEN_COMMAND  Override launcher executable; receives the attach command as $1
USAGE
}

wtx::check_required_tools() {
  wtx::reset_tool_tracking

  if need git; then
    wtx::append_tool_summary "git:ok"
  else
    wtx::append_tool_summary "git:miss"
    wtx::record_missing_tool git
  fi

  if need socat; then
    wtx::append_tool_summary "socat:ok"
  else
    wtx::append_tool_summary "socat:miss"
    wtx::record_missing_tool socat
  fi

  if need uv; then
    wtx::append_tool_summary "uv:ok"
  else
    wtx::append_tool_summary "uv:miss"
  fi

  if need pnpm; then
    wtx::append_tool_summary "pnpm:ok"
  else
    wtx::append_tool_summary "pnpm:miss"
  fi

  wtx::print_tool_summary
}

wtx::sanitize_name() {
  printf '%s' "$1" | tr '/:' '__'
}

wtx::sanitize_commit_payload() {
  local payload="$1"
  payload=${payload//$'\n'/ }
  payload=$(printf '%s' "$payload" | tr '\000-\037' ' ')
  printf '%s' "${payload:0:200}"
}

wtx::run_git_log_commit() {
  local message="$1"
  : "${GIT_LOGGING:=1}"
  if [ "$GIT_LOGGING" -eq 0 ]; then
    return
  fi
  git -C "$WT_DIR" commit --allow-empty -m "$message" >/dev/null 2>&1 || true
}
