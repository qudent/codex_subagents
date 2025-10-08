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
  unset TMUX
}

teardown() {
  tmux kill-server >/dev/null 2>&1 || true
  if screen -ls >/dev/null 2>&1; then
    # Kill any screen sessions we started (ignore errors if none)
    screen -ls | awk '/\t/ {print $1}' | while read -r ses; do
      screen -S "$ses" -X quit >/dev/null 2>&1 || true
    done
  fi
  rm -rf "$TEST_ROOT"
}

wtx() {
  (cd "$REPO_ROOT" && "$BATS_TEST_DIRNAME/../wtx" "$@")
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

@test "tmux backend prints banner and runs -c command" {
  branch="feature/test-cmd"
  run wtx "$branch" --no-open -c "echo RUN_MARKER"
  [ "$status" -eq 0 ]
  sleep 1
  ses="wtx_$(sanitize "$(basename "$REPO_ROOT")")_$(sanitize "$branch")"
  run tmux capture-pane -t "$ses" -p
  [ "$status" -eq 0 ]
  [[ "$output" == *"wtx: repo=$(basename "$REPO_ROOT") branch=$branch"* ]]
  [[ "$output" == *"RUN_MARKER"* ]]
}

@test "screen backend prints banner" {
  branch="screen-test"
  export MUX=screen
  run wtx "$branch" --no-open
  unset MUX
  [ "$status" -eq 0 ]
  sleep 1
  ses="wtx_$(sanitize "$(basename "$REPO_ROOT")")_$(sanitize "$branch")"
  hardcopy="$TEST_ROOT/screen.out"
  screen -S "$ses" -p 0 -X hardcopy "$hardcopy"
  run cat "$hardcopy"
  [ "$status" -eq 0 ]
  [[ "$output" == *"wtx: repo=$(basename "$REPO_ROOT") branch=$branch"* ]]
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

@test "tmux ready flag set" {
  run wtx ready-branch --no-open
  [ "$status" -eq 0 ]
  sleep 1
  ses="wtx_$(sanitize "$(basename "$REPO_ROOT")")_$(sanitize "ready-branch")"
  run tmux show-option -t "$ses" -v @wtx_ready
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "uv env created once" {
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
