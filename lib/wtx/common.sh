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
wtx — create/reuse a git worktree and open a tmux/screen session with a one-line banner.

Usage: wtx [NAME] [-c CMD] [--from REF] [--mux auto|tmux|screen] [--no-open]
            [--dry-run] [--verbose] [--delete-branches] [--no-git-logging]
            [--_post-commit]
Examples:
  wtx                       # auto-name branch wtx/<parent>-NN, create worktree + session
  wtx feature-xyz -c 'pytest -q'   # send raw keystrokes after session is ready
  wtx --mux screen          # use GNU screen if you prefer

Flags:
  -c CMD            Send raw keystrokes to pane (exactly, then Enter)
  --from REF        Use REF as starting point (default: HEAD)
  --mux MODE        auto|tmux|screen   (default: auto)
  --no-open         Do not attach/switch to the session; only print attach command
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
  local have_tmux=0
  local have_screen=0

  if need git; then
    wtx::append_tool_summary "git:ok"
  else
    wtx::append_tool_summary "git:miss"
    wtx::record_missing_tool git
  fi

  if need tmux; then
    have_tmux=1
    wtx::append_tool_summary "tmux:ok"
  else
    wtx::append_tool_summary "tmux:miss"
  fi

  if need screen; then
    have_screen=1
    wtx::append_tool_summary "screen:ok"
  else
    if [ $have_tmux -eq 1 ]; then
      wtx::append_tool_summary "screen:skip"
    else
      wtx::append_tool_summary "screen:miss"
    fi
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

  if [ $have_tmux -eq 0 ] && [ $have_screen -eq 0 ]; then
    wtx::record_missing_tool "tmux|screen"
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
