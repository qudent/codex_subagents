# shellcheck shell=bash

wtx::install_init_template() {
  local init="$WT_STATE_DIR/wtx-init.sh"
  if [ ! -f "$init" ]; then
    cat >"$init" <<'INIT'
# wtx init (sourced inside tmux/screen)
if [ -n "${WTX_UV_ENV:-}" ] && [ -d "$WTX_UV_ENV/bin" ]; then
  case ":$PATH:" in
    *:"$WTX_UV_ENV/bin":*) : ;;
    *) PATH="$WTX_UV_ENV/bin:$PATH" ;;
  esac
  export PATH
fi
if [ "${WTX_PROMPT:-0}" = "1" ]; then
  PS1="[wtx:${BRANCH_NAME}] $PS1"
fi
printf 'wtx: repo=%s branch=%s parent=%s from=%s actions=[%s]\n' "${REPO_BASENAME:-?}" "${BRANCH_NAME:-?}" "${PARENT_LABEL:-?}" "${FROM_REF:-?}" "${ACTIONS:-?}"
if command -v tmux >/dev/null 2>&1 && [ -n "${SES_NAME:-}" ]; then
  tmux set-option -t "$SES_NAME" @wtx_ready 1 2>/dev/null || true
fi
if [ -n "${READY_FILE:-}" ]; then
  : >"$READY_FILE"
fi
INIT
  fi
  INIT_SCRIPT="$init"
}

wtx::resolve_backend() {
  if [ "$MUX" = "auto" ]; then
    if need tmux; then
      MUX=tmux
    elif need screen; then
      MUX=screen
    fi
  fi

  if [ "$MUX" = "tmux" ] && ! need tmux; then
    echo "tmux backend requested but tmux not available." >&2
    exit 2
  fi

  if [ "$MUX" = "screen" ] && ! need screen; then
    echo "screen backend requested but screen not available." >&2
    exit 2
  fi
}

wtx::derive_parent_label() {
  if [ "$PARENT_BRANCH" = "detached" ]; then
    PARENT_LABEL="detached@${PARENT_SHORT}"
  else
    PARENT_LABEL="$PARENT_BRANCH"
  fi
}

wtx::compute_session_name() {
  local ses_repo ses_branch
  ses_repo=$(wtx::sanitize_name "$REPO_BASENAME")
  ses_branch=$(wtx::sanitize_name "$BRANCH_NAME")
  SES_NAME="wtx_${ses_repo}_${ses_branch}"
}

wtx::compute_attach_command() {
  case "$MUX" in
    tmux)
      ATTACH_COMMAND="tmux attach -t $SES_NAME"
      ;;
    screen)
      ATTACH_COMMAND="screen -r $SES_NAME"
      ;;
    *)
      ATTACH_COMMAND=""
      ;;
  esac
}

wtx::launch_tmux_session() {
  SESSION_STATUS="reused"
  if ! tmux has-session -t "$SES_NAME" 2>/dev/null; then
    tmux new-session -d -s "$SES_NAME" -c "$WT_DIR"
    SESSION_STATUS="created"
  fi
  tmux set-option -t "$SES_NAME" @wtx_repo_id "$REPO_ID" 2>/dev/null || true
  tmux set-option -t "$SES_NAME" @wtx_branch "$BRANCH_NAME" 2>/dev/null || true
}

wtx::launch_screen_session() {
  SESSION_STATUS="reused"
  if ! screen -ls | grep -q "\.${SES_NAME}[[:space:]]"; then
    screen -dmS "$SES_NAME" sh -c "cd $(printf %q "$WT_DIR"); exec \$SHELL"
    SESSION_STATUS="created"
  fi
}

wtx::launch_session() {
  wtx::derive_parent_label
  wtx::compute_session_name
  case "$MUX" in
    tmux)
      wtx::launch_tmux_session
      ;;
    screen)
      wtx::launch_screen_session
      ;;
    *)
      SESSION_STATUS="skipped"
      ;;
  esac
}

wtx::maybe_spawn_window() {
  OPEN_STATUS="suppressed"
  if [ $NO_OPEN -ne 0 ]; then
    return 1
  fi

  if [ -z "$ATTACH_COMMAND" ]; then
    OPEN_STATUS="failed"
    return 1
  fi

  if wtx::open_session_window "$ATTACH_COMMAND"; then
    return 0
  fi

  OPEN_STATUS="failed"
  return 1
}

wtx::build_env_exports() {
  printf 'WTX_UV_ENV=%q REPO_BASENAME=%q BRANCH_NAME=%q PARENT_LABEL=%q FROM_REF=%q ACTIONS=%q WTX_PROMPT=%q READY_FILE=%q SES_NAME=%q' \
    "$WTX_UV_ENV" "$REPO_BASENAME" "$BRANCH_NAME" "$PARENT_LABEL" "$FROM_REF" "$ACTIONS" "$WTX_PROMPT" "$READY_FILE" "$SES_NAME"
}

wtx::send_init_to_session() {
  local env_exports
  env_exports=$(wtx::build_env_exports)
  case "$MUX" in
    tmux)
      tmux send-keys -t "$SES_NAME" "$env_exports . $(printf %q "$INIT_SCRIPT")" C-m
      ;;
    screen)
      screen -S "$SES_NAME" -p 0 -X stuff "$env_exports . $(printf %q "$INIT_SCRIPT")$(printf '\r')"
      ;;
  esac
}

wtx::tmux_ready() {
  tmux show-option -t "$SES_NAME" -v @wtx_ready 2>/dev/null | grep -q '^1$'
}

wtx::wait_for_tmux_ready() {
  local i=0
  while [ $i -lt 5 ]; do
    if wtx::tmux_ready; then
      return 0
    fi
    sleep 0.04
    i=$(( i + 1 ))
  done
  return 1
}

wtx::wait_for_screen_ready() {
  local i=0
  while [ $i -lt 5 ]; do
    if [ -n "$READY_FILE" ] && [ -f "$READY_FILE" ]; then
      return 0
    fi
    sleep 0.04
    i=$(( i + 1 ))
  done
  return 1
}

wtx::dispatch_command() {
  [ -n "$CMD" ] || return 0
  case "$MUX" in
    tmux)
      wtx::wait_for_tmux_ready || true
      tmux send-keys -t "$SES_NAME" "$CMD" C-m
      ;;
    screen)
      wtx::wait_for_screen_ready || true
      screen -S "$SES_NAME" -p 0 -X stuff "$CMD$(printf '\r')"
      ;;
  esac
}

wtx::write_log_entry() {
  local logf tmp_log
  logf="$WTX_GIT_DIR_ABS/logs/$(date +%F).log"
  tmp_log=$(mktemp "$WTX_GIT_DIR_ABS/tmp.log.XXXXXX")
  printf '%s %s actions=[%s]\n' "$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z')" "$BRANCH_NAME" "$ACTIONS" >>"$tmp_log"
  cat "$tmp_log" >>"$logf" || true
  rm -f "$tmp_log" || true
}

wtx::main() {
  wtx::set_defaults
  wtx::parse_args "$@"
  wtx::check_required_tools
  wtx::init_repo_context
  wtx::compute_repo_id

  if [ "$INTERNAL_POST_COMMIT" -eq 1 ]; then
    wtx::handle_post_commit
    return
  fi

  wtx::normalize_messaging_policy
  wtx::determine_parent_branch
  wtx::acquire_number_lock "$PARENT_BRANCH"
  wtx::select_branch_name
  wtx::prepare_branch_state
  wtx::ensure_branch_exists
  wtx::record_branch_metadata
  wtx::ensure_worktree_root
  wtx::prune_stale_worktree
  wtx::ensure_worktree_present
  wtx::ensure_uv_env
  wtx::ensure_pnpm
  wtx::install_init_template
  wtx::install_post_commit_hook
  wtx::resolve_backend
  wtx::launch_session
  wtx::compute_attach_command

  wtx::maybe_spawn_window || true
  ACTIONS="env:${ENV_STATUS}, pnpm:${PNPM_STATUS}, session:${SESSION_STATUS}, open:${OPEN_STATUS}"

  wtx::send_init_to_session

  if [ "$WORKTREE_STATUS" = "created" ]; then
    wtx::run_git_log_commit "WTX_SPINUP: branch=$BRANCH_NAME from=$FROM_REF"
  fi

  if [ -n "$CMD" ]; then
    wtx::run_git_log_commit "WTX_COMMAND: $(wtx::sanitize_commit_payload "$CMD")"
  fi

  wtx::dispatch_command
  wtx::write_log_entry

  if [ -n "$ATTACH_COMMAND" ]; then
    printf '[wtx] Attach with: %s\n' "$ATTACH_COMMAND"
  fi
}
