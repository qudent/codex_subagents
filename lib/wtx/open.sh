# shellcheck shell=bash

wtx::default_open_strategy() {
  echo "iterm,apple-terminal,kitty,alacritty,wezterm,gnome-terminal,foot,xterm,print"
}

wtx::normalize_strategy_token() {
  printf '%s' "$1" | tr 'A-Z' 'a-z' | tr -d ' \t\n\r'
}

wtx::spawn_detached() {
  if command -v setsid >/dev/null 2>&1; then
    (setsid "$@" >/dev/null 2>&1 &)
  else
    ("$@" >/dev/null 2>&1 &)
  fi
}

wtx::open_strategy_iterm() {
  if [ "$(uname -s 2>/dev/null)" != "Darwin" ]; then
    return 1
  fi
  if ! need osascript; then
    return 1
  fi
  local cmd="$1"
  if osascript <<OSA
try
  tell application "iTerm2"
    activate
    set newWindow to (create window with default profile)
    tell current session of newWindow
      write text "$cmd"
    end tell
  end tell
  return "ok"
on error
  tell application "iTerm"
    activate
    set newWindow to (create window with default profile)
    tell current session of newWindow
      write text "$cmd"
    end tell
  end tell
  return "ok"
end try
OSA
  then
    OPEN_STATUS="spawned"
    return 0
  fi
  return 1
}

wtx::open_strategy_apple_terminal() {
  if [ "$(uname -s 2>/dev/null)" != "Darwin" ]; then
    return 1
  fi
  if ! need osascript; then
    return 1
  fi
  local cmd="$1"
  if osascript <<OSA
activate application "Terminal"
tell application "Terminal"
  do script "$cmd"
  activate
end tell
OSA
  then
    OPEN_STATUS="spawned"
    return 0
  fi
  return 1
}

wtx::open_strategy_kitty() {
  if ! need kitty; then
    return 1
  fi
  local cmd="$1"
  if wtx::spawn_detached kitty bash -lc "$cmd"; then
    OPEN_STATUS="spawned"
    return 0
  fi
  return 1
}

wtx::open_strategy_alacritty() {
  if ! need alacritty; then
    return 1
  fi
  local cmd="$1"
  if wtx::spawn_detached alacritty -e bash -lc "$cmd"; then
    OPEN_STATUS="spawned"
    return 0
  fi
  return 1
}

wtx::open_strategy_wezterm() {
  if ! need wezterm; then
    return 1
  fi
  local cmd="$1"
  if wtx::spawn_detached wezterm start -- bash -lc "$cmd"; then
    OPEN_STATUS="spawned"
    return 0
  fi
  return 1
}

wtx::open_strategy_gnome_terminal() {
  if ! need gnome-terminal; then
    return 1
  fi
  local cmd="$1"
  if wtx::spawn_detached gnome-terminal -- bash -lc "$cmd"; then
    OPEN_STATUS="spawned"
    return 0
  fi
  return 1
}

wtx::open_strategy_foot() {
  if ! need foot; then
    return 1
  fi
  local cmd="$1"
  if wtx::spawn_detached foot -- bash -lc "$cmd"; then
    OPEN_STATUS="spawned"
    return 0
  fi
  return 1
}

wtx::open_strategy_xterm() {
  if ! need xterm; then
    return 1
  fi
  local cmd="$1"
  if wtx::spawn_detached xterm -e bash -lc "$cmd"; then
    OPEN_STATUS="spawned"
    return 0
  fi
  return 1
}

wtx::open_strategy_print() {
  OPEN_STATUS="suppressed"
  return 0
}

wtx::open_session_window() {
  local attach_command="$1"
  local strategies="${WTX_OPEN_STRATEGY:-$(wtx::default_open_strategy)}"
  local success=1
  local raw strategy func
  IFS=','
  for raw in $strategies; do
    IFS=$' \t\n\r' read -r strategy _ <<<"$raw"
    strategy=$(wtx::normalize_strategy_token "$strategy")
    [ -n "$strategy" ] || continue
    func="wtx::open_strategy_${strategy//-/_}"
    if declare -f "$func" >/dev/null 2>&1; then
      if "$func" "$attach_command"; then
        success=0
        break
      fi
    fi
  done
  IFS=$'\n\t'
  if [ $success -ne 0 ]; then
    OPEN_STATUS="failed"
    return 1
  fi
  return 0
}
