# shellcheck shell=bash

wtx::install_init_template() {
  local init="$WT_STATE_DIR/wtx-init.sh"
  if [ ! -f "$init" ]; then
    cat >"$init" <<'INIT'
# wtx init (sourced inside socat shell)
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
if [ -n "${READY_FILE:-}" ]; then
  : >"$READY_FILE"
fi
INIT
  fi
  INIT_SCRIPT="$init"
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

wtx::prepare_session_paths() {
  SESSION_DIR="$WTX_GIT_DIR_ABS/sessions"
  mkdir -p "$SESSION_DIR"
  SES_PTY="$SESSION_DIR/$SES_NAME.pty"
  SES_PID_FILE="$SESSION_DIR/$SES_NAME.pid"
  SES_LOG="$SESSION_DIR/$SES_NAME.log"
}

wtx::session_pid_alive() {
  if [ ! -f "$SES_PID_FILE" ]; then
    return 1
  fi
  local pid
  pid=$(cat "$SES_PID_FILE" 2>/dev/null || true)
  if [ -z "$pid" ]; then
    rm -f "$SES_PID_FILE" || true
    return 1
  fi
  if kill -0 "$pid" 2>/dev/null && [ -e "$SES_PTY" ]; then
    return 0
  fi
  rm -f "$SES_PID_FILE" || true
  return 1
}

wtx::wait_for_session_channel() {
  local attempts=0
  while [ $attempts -lt 50 ]; do
    if [ -e "$SES_PTY" ]; then
      return 0
    fi
    sleep 0.02
    attempts=$(( attempts + 1 ))
  done
  return 1
}

wtx::start_socat_process() {
  rm -f "$SES_PTY" "$SES_PID_FILE"
  SESSION_STATUS="created"
  local exec_cmd
  exec_cmd=$(printf 'cd %s && exec ${SHELL:-bash} -i' "$(printf %q "$WT_DIR")")
  if command -v setsid >/dev/null 2>&1; then
    setsid socat -lf "$SES_LOG" PTY,link="$SES_PTY",rawer,echo=0,wait-slave EXEC:"$exec_cmd",pty,setsid,ctty >/dev/null 2>&1 &
  else
    socat -lf "$SES_LOG" PTY,link="$SES_PTY",rawer,echo=0,wait-slave EXEC:"$exec_cmd",pty,setsid,ctty >/dev/null 2>&1 &
  fi
  local pid=$!
  sleep 0.05
  if ! kill -0 "$pid" 2>/dev/null; then
    SESSION_STATUS="failed"
    return 1
  fi
  echo "$pid" >"$SES_PID_FILE"
  if ! wtx::wait_for_session_channel; then
    SESSION_STATUS="failed"
    return 1
  fi
  return 0
}

wtx::ensure_session_process() {
  if wtx::session_pid_alive; then
    SESSION_STATUS="reused"
    return 0
  fi
  wtx::start_socat_process
}

wtx::compute_attach_command() {
  if [ -e "$SES_PTY" ]; then
    ATTACH_COMMAND="socat - FILE:$SES_PTY,raw,echo=0"
  else
    ATTACH_COMMAND=""
  fi
}

wtx::launch_session() {
  wtx::derive_parent_label
  wtx::compute_session_name
  wtx::prepare_session_paths
  SESSION_STATUS="failed"
  if wtx::ensure_session_process; then
    wtx::compute_attach_command
  else
    ATTACH_COMMAND=""
  fi
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

wtx::send_to_session() {
  local payload="$1"
  if [ -z "$SES_PTY" ] || [ ! -e "$SES_PTY" ]; then
    return 1
  fi
  printf '%s' "$payload" | socat - "FILE:$SES_PTY,raw,echo=0" >/dev/null 2>&1
}

wtx::send_init_to_session() {
  local env_exports payload
  env_exports=$(wtx::build_env_exports)
  payload="cd $(printf %q "$WT_DIR")"$'\n'
  payload+="$env_exports . $(printf %q "$INIT_SCRIPT")"$'\n'
  wtx::send_to_session "$payload"
}

wtx::wait_for_ready_file() {
  local i=0
  while [ $i -lt 50 ]; do
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
  wtx::wait_for_ready_file || true
  local payload="$CMD"$'\n'
  wtx::send_to_session "$payload"
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
  wtx::launch_session

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
