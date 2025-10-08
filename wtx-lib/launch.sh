# launch orchestration

wtx_prepare_env() {
  WTX_UV_ENV=${WTX_UV_ENV:-"$HOME/.wtx/uv-shared"}
  WTX_PROMPT=${WTX_PROMPT:-0}
  ENV_ACTION="none"
  if need uv; then
    if [ ! -d "$WTX_UV_ENV" ]; then
      uv venv "$WTX_UV_ENV"
    fi
    ENV_ACTION="linked"
  fi
}

wtx_prepare_pnpm() {
  PNPM_STATUS="none"
  if [ -f "$WT_DIR/package.json" ] && need pnpm; then
    PNPM_STAMP="$WT_DIR/.wtx_pnpm_stamp"
    if [ ! -d "$WT_DIR/node_modules" ] || { [ -f "$WT_DIR/pnpm-lock.yaml" ] && [ "$WT_DIR/pnpm-lock.yaml" -nt "$PNPM_STAMP" ]; }; then
      ( cd "$WT_DIR" && pnpm install --frozen-lockfile )
      tmp=$(mktemp "$WT_DIR/.wtx_pnpm.XXXXXX"); date +%s >"$tmp"; mv "$tmp" "$PNPM_STAMP"
      PNPM_STATUS="installed"
    else
      PNPM_STATUS="skipped"
    fi
  fi
}

wtx_log_run() {
  logf="$WTX_GIT_DIR_ABS/logs/$(date +%F).log"
  tmp=$(mktemp "$WTX_GIT_DIR_ABS/tmp.XXXXXX")
  printf '%s %s actions=[%s]\n' "$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z')" "$BRANCH_NAME" "$ACTIONS" >>"$tmp"
  cat "$tmp" >>"$logf" || true
  rm -f "$tmp" || true
}

wtx_launch_branch() {
  wtx_prepare_branch_selection
  wtx_ensure_branch_materialized
  wtx_ensure_worktree
  wtx_prepare_env
  wtx_prepare_pnpm

  if [ "$PARENT_BRANCH" = "detached" ]; then
    PARENT_LABEL="detached@${PARENT_SHORT}"
  else
    PARENT_LABEL="$PARENT_BRANCH"
  fi

  SES_NAME=$(wtx_session_name_for_branch "$BRANCH_NAME")
  ACTIONS="env:${ENV_ACTION}, pnpm:${PNPM_STATUS}"

  wtx_ensure_init_script

  wtx_mux_select_backend
  wtx_mux_plan_session
  wtx_mux_launch_session
  wtx_log_run

  if [ -n "$ATTACH_CMD" ]; then
    echo "[wtx] Attach with: $ATTACH_CMD"
  fi

  if [ "$CLOSE_AFTER" -eq 1 ]; then
    wtx_close_branch "$BRANCH_NAME" "$CLOSE_MODE"
  fi
}
