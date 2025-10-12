#!/usr/bin/env bats

setup() {
  export TEST_ROOT="$(mktemp -d)"
  export REPO_ROOT="$TEST_ROOT/repo"
  mkdir -p "$REPO_ROOT"
  git -C "$REPO_ROOT" init >/dev/null
  git -C "$REPO_ROOT" config user.name "Test User"
  git -C "$REPO_ROOT" config user.email "test@example.com"
  echo "initial" >"$REPO_ROOT/README.md"
  git -C "$REPO_ROOT" add README.md
  git -C "$REPO_ROOT" commit -m "init" >/dev/null
  git -C "$REPO_ROOT" branch -M main >/dev/null
  export HOME="$TEST_ROOT/home"
  mkdir -p "$HOME"
  unset WTX_UV_ENV
  export UV_CACHE_DIR="$TEST_ROOT/uv-cache"
  unset WTX_OPEN_COMMAND
  export WTX_BIN="$BATS_TEST_DIRNAME/../wtx"
  mkdir -p "$TEST_ROOT/bin"
  cat >"$TEST_ROOT/bin/uv" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "venv" ]; then
  mkdir -p "$2/bin"
  echo "venv" >>"$TEST_ROOT/uv_calls"
  exit 0
fi
echo "unsupported" >&2
exit 1
EOF
  chmod +x "$TEST_ROOT/bin/uv"
  export PATH="$TEST_ROOT/bin:$PATH"
}

teardown() {
  if [ -d "$REPO_ROOT/.git/wtx/sessions" ]; then
    for pid_file in "$REPO_ROOT/.git/wtx/sessions"/*.pid; do
      [ -e "$pid_file" ] || continue
      pid=$(cat "$pid_file" 2>/dev/null || true)
      if [ -n "$pid" ]; then
        kill "$pid" >/dev/null 2>&1 || true
      fi
    done
  fi
  rm -rf "$TEST_ROOT"
}

wtx() {
  (cd "$REPO_ROOT" && "$WTX_BIN" "$@")
}

sanitize() {
  printf '%s' "$1" | tr '/:' '__'
}

@test "auto branch naming creates sequential worktrees" {
  run wtx --no-open
  [ "$status" -eq 0 ]
  run git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/wtx/main-1"
  [ "$status" -eq 0 ]
  run wtx --no-open
  [ "$status" -eq 0 ]
  run git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/wtx/main-2"
  [ "$status" -eq 0 ]
  [ -d "$(dirname "$REPO_ROOT")/$(basename "$REPO_ROOT").worktrees/wtx_main-1" ]
}

@test "socat session prints banner and runs -c command" {
  branch="feature/test-cmd"
  run wtx "$branch" --no-open -c "echo RUN_MARKER"
  [ "$status" -eq 0 ]
  ses="wtx_$(sanitize "$(basename "$REPO_ROOT")")_$(sanitize "$branch")"
  pty="$REPO_ROOT/.git/wtx/sessions/${ses}.pty"
  for attempt in $(seq 1 10); do
    [ -e "$pty" ] && break
    sleep 0.1
  done
  [ -e "$pty" ]
  run python3 <<'PYR'
import fcntl
import os
import sys
import time

pty_path = sys.argv[1]
fd = os.open(pty_path, os.O_RDWR | os.O_NOCTTY)
flags = fcntl.fcntl(fd, fcntl.F_GETFL)
fcntl.fcntl(fd, fcntl.F_SETFL, flags | os.O_NONBLOCK)

end = time.time() + 2.0
chunks = []
while time.time() < end:
    try:
        data = os.read(fd, 4096)
    except BlockingIOError:
        data = b''
    if data:
        chunks.append(data)
        if b'RUN_MARKER' in data and b'wtx:' in data:
            break
    time.sleep(0.05)

os.close(fd)
sys.stdout.write(b''.join(chunks).decode('utf-8', 'ignore'))
PYR
  [ "$status" -eq 0 ]
  [[ "$output" == *"wtx: repo=$(basename "$REPO_ROOT") branch=$branch"* ]]
  [[ "$output" == *"RUN_MARKER"* ]]
}

@test "log records actions" {
  run wtx --no-open
  [ "$status" -eq 0 ]
  log_file="$REPO_ROOT/.git/wtx/logs/$(date +%F).log"
  [ -f "$log_file" ]
  run tail -n 1 "$log_file"
  [ "$status" -eq 0 ]
  [[ "$output" == *"actions=["* ]]
  [[ "$output" == *"session:"* ]]
}

@test "ready file is created" {
  branch="ready-branch"
  run wtx "$branch" --no-open
  [ "$status" -eq 0 ]
  ready_file="$REPO_ROOT/.git/wtx/state/$(sanitize "$branch").ready"
  for attempt in $(seq 1 25); do
    [ -f "$ready_file" ] && break
    sleep 0.05
  done
  [ -f "$ready_file" ]
}

@test "uv env created once" {
  rm -f "$TEST_ROOT/uv_calls"
  unset WTX_UV_ENV
  run wtx uv-one --no-open
  [ "$status" -eq 0 ]
  run wtx uv-two --no-open
  [ "$status" -eq 0 ]
  calls=$(wc -l <"$TEST_ROOT/uv_calls")
  [ "$calls" -eq 1 ]
  repo_venv="$(git -C "$REPO_ROOT" rev-parse --absolute-git-dir)/../.venv"
  [ -d "$repo_venv/bin" ]
}

@test "git logging commits commands" {
  branch="log-test"
  run wtx "$branch" --no-open -c "echo ONE"
  [ "$status" -eq 0 ]
  run wtx "$branch" --no-open -c "echo TWO"
  [ "$status" -eq 0 ]
  count=$(git -C "$REPO_ROOT" log --pretty=%s "$branch" | grep -c '^WTX_COMMAND:')
  [ "$count" -eq 2 ]
  run wtx "$branch" --no-open --no-git-logging -c "echo THREE"
  [ "$status" -eq 0 ]
  count_after=$(git -C "$REPO_ROOT" log --pretty=%s "$branch" | grep -c '^WTX_COMMAND:')
  [ "$count_after" -eq 2 ]
}

@test "override open command runs custom handler" {
  override="$TEST_ROOT/open-override.sh"
  cat >"$override" <<EOF
#!/usr/bin/env bash
printf '%s\n' "$1" >> "$TEST_ROOT/open.log"
EOF
  chmod +x "$override"
  export WTX_OPEN_COMMAND="$override"

  run wtx gui-override
  [ "$status" -eq 0 ]
  [[ "$output" == *"[wtx] Attach with: socat - FILE:"* ]]

  sleep 1
  log_capture="$TEST_ROOT/open.log"
  [ -f "$log_capture" ]
  run cat "$log_capture"
  [ "$status" -eq 0 ]
  [[ "$output" == *"socat - FILE:"* ]]

  log_file="$REPO_ROOT/.git/wtx/logs/$(date +%F).log"
  run tail -n 1 "$log_file"
  [ "$status" -eq 0 ]
  [[ "$output" == *"open:spawned"* ]]
}

@test "missing open command records failure" {
  export WTX_OPEN_COMMAND=/nonexistent/wtx-open
  run wtx gui-fallback
  [ "$status" -eq 0 ]
  [[ "$output" == *"[wtx] Attach with: socat - FILE:"* ]]
  log_file="$REPO_ROOT/.git/wtx/logs/$(date +%F).log"
  run tail -n 1 "$log_file"
  [ "$status" -eq 0 ]
  [[ "$output" == *"open:failed"* ]]
}

@test "post-commit hook installs and broadcasts to parent" {
  run wtx --no-open
  [ "$status" -eq 0 ]
  hook="$REPO_ROOT/.git/hooks/post-commit"
  [ -f "$hook" ]
  run grep -q '# wtx post-commit hook' "$hook"
  [ "$status" -eq 0 ]

  parent_branch="wtx/main-1"
  parent_wt="$(dirname "$REPO_ROOT")/$(basename "$REPO_ROOT").worktrees/$(sanitize "$parent_branch")"
  run bash -c "cd '$parent_wt' && '$WTX_BIN' --no-open"
  [ "$status" -eq 0 ]

  child_branch="wtx/${parent_branch}-1"
  child_root="$(dirname "$parent_wt")/$(basename "$parent_wt").worktrees"
  child_wt="$child_root/$(sanitize "$child_branch")"
  [ -d "$child_wt" ]

  parent_session="wtx_$(sanitize "$(basename "$REPO_ROOT")")_$(sanitize "wtx/main-1")"
  parent_pty="$REPO_ROOT/.git/wtx/sessions/${parent_session}.pty"
  for attempt in $(seq 1 20); do
    [ -e "$parent_pty" ] && break
    sleep 0.05
  done
  [ -e "$parent_pty" ]

  pipe_log="$TEST_ROOT/pipe.log"
  python3 <<'PYR'
import fcntl
import os
import sys
import time

pty_path, log_path = sys.argv[1:3]
fd = os.open(pty_path, os.O_RDWR | os.O_NOCTTY)
flags = fcntl.fcntl(fd, fcntl.F_GETFL)
fcntl.fcntl(fd, fcntl.F_SETFL, flags | os.O_NONBLOCK)

deadline = time.time() + 6.0
with open(log_path, 'wb') as log:
    while time.time() < deadline:
        try:
            chunk = os.read(fd, 4096)
        except BlockingIOError:
            chunk = b''
        if chunk:
            log.write(chunk)
            log.flush()
            if b'# [wtx]' in chunk:
                break
        time.sleep(0.05)

os.close(fd)
PYR
  listener_pid=$!

  echo "child" >>"$child_wt/README.md"
  git -C "$child_wt" add README.md
  git -C "$child_wt" commit -m "child commit" >/dev/null
  run bash -c "cd '$child_wt' && '$WTX_BIN' --_post-commit"
  [ "$status" -eq 0 ]

  wait "$listener_pid"
  tr -d '\r' <"$pipe_log" | grep -q '# \[wtx] wtx/wtx/main-1-1 commit'
}

@test "invalid messaging policy exits" {
  export WTX_MESSAGING_POLICY=bogus
  run wtx --no-open
  [ "$status" -eq 64 ]
  [[ "$output" == *"Invalid WTX_MESSAGING_POLICY"* ]]
}
