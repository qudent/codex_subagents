# tmux/screen helpers

try_gui_attach() {
  cmd="$1"
  [ -n "$cmd" ] || return 1
  if need osascript; then
    escaped=$(printf '%s' "$cmd" | sed 's/"/\\"/g')
    if osascript <<OSA >/dev/null 2>&1
set targetApp to "Terminal"
tell application targetApp
  activate
  do script "$escaped"
end tell
OSA
    then
      return 0
    fi
  fi
  if [ -n "${WTX_TERMINAL:-}" ] && need "$WTX_TERMINAL"; then
    "$WTX_TERMINAL" -e sh -c "$cmd" >/dev/null 2>&1 &
    return 0
  fi
  if need x-terminal-emulator; then
    x-terminal-emulator -e sh -c "$cmd" >/dev/null 2>&1 &
    return 0
  fi
  return 1
}

wtx_kill_sessions_for_branch() {
  branch="$1"
  ses=$(wtx_session_name_for_branch "$branch")
  if need tmux && tmux has-session -t "$ses" 2>/dev/null; then
    tmux kill-session -t "$ses" >/dev/null 2>&1 || true
  fi
  if need screen && screen -ls 2>/dev/null | grep -q "\.${ses}[[:space:]]"; then
    screen -S "$ses" -X quit >/dev/null 2>&1 || true
  fi
}

wtx_mux_select_backend() {
  if [ "$MUX" = "auto" ]; then
    if need tmux; then
      MUX=tmux
    elif need screen; then
      MUX=screen
    else
      die "Need tmux or screen installed."
    fi
  fi
  logv "mux=$MUX"
}

wtx_ensure_init_script() {
  INIT="$WTX_GIT_DIR_ABS/state/wtx-init.sh"
  if [ -f "$INIT" ]; then
    return
  fi
  cat >"$INIT" <<'EOS'
# wtx init (sourced inside tmux/screen session)
if [ -n "${WTX_UV_ENV:-}" ] && [ -d "$WTX_UV_ENV/bin" ]; then
  PATH="$WTX_UV_ENV/bin:$PATH"; export PATH
fi
if [ "${WTX_PROMPT:-0}" = "1" ]; then
  PS1="[wtx:${BRANCH_NAME}] $PS1"
fi
export WTX_UV_ENV REPO_BASENAME BRANCH_NAME PARENT_LABEL FROM_REF ACTIONS WTX_PROMPT
if command -v tmux >/dev/null 2>&1; then
  tmux set-option -t "$(tmux display-message -p '#S' 2>/dev/null)" @wtx_ready 1 2>/dev/null || true
fi
EOS
}

wtx_tmux_repo_match() {
  session="$1"
  tmux show-options -v -t "$session" @wtx_repo_id 2>/dev/null || echo ""
}

wtx_mux_plan_session() {
  if [ "$MUX" = "tmux" ]; then
    if tmux has-session -t "$SES_NAME" 2>/dev/null; then
      SESSION_ACTION="reattach"
    else
      SESSION_ACTION="created"
    fi
  elif [ "$MUX" = "screen" ]; then
    if screen -ls 2>/dev/null | grep -q "\.${SES_NAME}[[:space:]]"; then
      SESSION_ACTION="reattach"
    else
      SESSION_ACTION="created"
    fi
  else
    SESSION_ACTION="created"
  fi
  ACTIONS="$ACTIONS, session:${SESSION_ACTION}"
  ENV_LINE="WTX_UV_ENV=$(q "$WTX_UV_ENV") REPO_BASENAME=$(q "$REPO_BASENAME") BRANCH_NAME=$(q "$BRANCH_NAME") PARENT_LABEL=$(q "$PARENT_LABEL") FROM_REF=$(q "$FROM_REF") ACTIONS=$(q "$ACTIONS") WTX_PROMPT=$(q "$WTX_PROMPT") . $(q "$INIT")"
  banner="wtx: repo=$REPO_BASENAME branch=$BRANCH_NAME parent=$PARENT_LABEL from=$FROM_REF actions=[$ACTIONS]"
  BANNER_LINE="printf '%s\\n' '$(printf "%s" "$banner" | sed "s/'/\\\\'/g")'"
}

wtx_mux_launch_session() {
  ATTACH_CMD=""
  if [ "$MUX" = "tmux" ]; then
    if ! tmux has-session -t "$SES_NAME" 2>/dev/null; then
      tmux new-session -d -s "$SES_NAME" -c "$WT_DIR"
      tmux set-option -t "$SES_NAME" @wtx_repo_id "$REPO_ID"
    fi
    tmux send-keys -t "$SES_NAME" "$ENV_LINE" C-m
    tmux send-keys -t "$SES_NAME" "$BANNER_LINE" C-m
    if [ -n "$CMD" ]; then
      tmux send-keys -t "$SES_NAME" "$CMD" C-m
    fi
    if [ $NO_OPEN -eq 0 ]; then
      attach_candidate="tmux attach -t '$SES_NAME'"
      if [ -n "${TMUX:-}" ]; then
        tmux switch-client -t "$SES_NAME"
      elif ! try_gui_attach "$attach_candidate"; then
        ATTACH_CMD="$attach_candidate"
        tmux attach -t "$SES_NAME"
      fi
    else
      ATTACH_CMD="tmux attach -t '$SES_NAME'"
    fi
  elif [ "$MUX" = "screen" ]; then
    if ! screen -ls 2>/dev/null | grep -q "\.${SES_NAME}[[:space:]]"; then
      screen -dmS "$SES_NAME" sh -c "cd $(q "$WT_DIR"); exec \$SHELL"
    fi
    screen -S "$SES_NAME" -p 0 -X stuff "$ENV_LINE$(printf '\r')"
    screen -S "$SES_NAME" -p 0 -X stuff "$BANNER_LINE$(printf '\r')"
    if [ -n "$CMD" ]; then
      screen -S "$SES_NAME" -p 0 -X stuff "$CMD$(printf '\r')"
    fi
    if [ $NO_OPEN -eq 0 ]; then
      attach_candidate="screen -r '$SES_NAME'"
      if ! try_gui_attach "$attach_candidate"; then
        ATTACH_CMD="$attach_candidate"
        screen -r "$SES_NAME"
      fi
    else
      ATTACH_CMD="screen -r '$SES_NAME'"
    fi
  fi
}
