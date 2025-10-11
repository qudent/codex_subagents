# shellcheck shell=bash

wtx::spawn_detached() {
  if command -v setsid >/dev/null 2>&1; then
    setsid "$@" >/dev/null 2>&1 &
  else
    "$@" >/dev/null 2>&1 &
  fi
}

wtx::command_exists() {
  local cmd="$1"
  if [ -z "$cmd" ]; then
    return 1
  fi

  if [[ "$cmd" = */* ]]; then
    [ -x "$cmd" ]
  else
    command -v "$cmd" >/dev/null 2>&1
  fi
}

wtx::open_with_override() {
  local attach_command="$1"
  local override="${WTX_OPEN_COMMAND:-}"
  [ -n "$override" ] || return 1

  if ! wtx::command_exists "$override"; then
    return 1
  fi

  if wtx::spawn_detached "$override" "$attach_command"; then
    OPEN_STATUS="spawned"
    return 0
  fi

  return 1
}

wtx::open_with_macos_terminal() {
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

wtx::open_with_xterm() {
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

wtx::open_session_window() {
  local attach_command="$1"
  local override="${WTX_OPEN_COMMAND:-}"

  if [ -n "$override" ]; then
    if wtx::open_with_override "$attach_command"; then
      return 0
    fi
    OPEN_STATUS="failed"
    return 1
  fi

  case "$(uname -s 2>/dev/null)" in
    Darwin)
      if wtx::open_with_macos_terminal "$attach_command"; then
        return 0
      fi
      ;;
    *)
      if wtx::open_with_xterm "$attach_command"; then
        return 0
      fi
      ;;
  esac

  return 1
}
