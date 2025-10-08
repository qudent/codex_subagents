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
  export WTX_UV_ENV="$HOME/.wtx/uv-shared"
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
  run tmux capture-pane -J -t "$ses" -p
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

worktree_path() {
  printf '%s/%s.worktrees/%s' "$(dirname "$REPO_ROOT")" "$(basename "$REPO_ROOT")" "$(sanitize "$1")"
}

session_name() {
  printf 'wtx_%s_%s' "$(sanitize "$(basename "$REPO_ROOT")")" "$(sanitize "$1")"
}

@test "close subcommand removes branch and worktree" {
  branch="feature/close"
  run wtx "$branch" --no-open
  [ "$status" -eq 0 ]
  wt_dir="$(worktree_path "$branch")"
  [ -d "$wt_dir" ]
  run wtx close "$branch"
  [ "$status" -eq 0 ]
  run git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/$branch"
  [ "$status" -ne 0 ]
  [ ! -d "$wt_dir" ]
}

@test "close merge auto commits and notifies sibling" {
  sibling="sibling"
  run wtx "$sibling" --no-open
  [ "$status" -eq 0 ]
  branch="feature/merge"
  run wtx "$branch" --no-open
  [ "$status" -eq 0 ]
  wt_dir="$(worktree_path "$branch")"
  echo "merge-data" >"$wt_dir/merge.txt"
  run wtx "$branch" --no-open --close-merge
  [ "$status" -eq 0 ]
  run git -C "$REPO_ROOT" ls-tree -r HEAD --name-only
  [ "$status" -eq 0 ]
  [[ "$output" == *"merge.txt"* ]]
  sleep 1
  ses="$(session_name "$sibling")"
  run tmux capture-pane -t "$ses" -p
  [ "$status" -eq 0 ]
  normalized="${output//$'\r'/}" # strip carriage returns from tmux
  normalized="${normalized//$'\n'/ }"
  compact="${normalized// /}"
  branch_compact="${branch// /}"
  regex="#[[]wtx]merge${branch_compact}->"
  [[ "$compact" =~ $regex ]]
}

@test "prune removes orphan sessions and directories" {
  branch="feature/prune"
  run wtx "$branch" --no-open
  [ "$status" -eq 0 ]
  wt_dir="$(worktree_path "$branch")"
  ses="$(session_name "$branch")"
  [ -d "$wt_dir" ]
  rm -rf "$wt_dir"
  run wtx prune --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"kill-session $ses (orphaned)"* ]]
  run wtx prune
  [ "$status" -eq 0 ]
  run tmux has-session -t "$ses" 2>/dev/null
  [ "$status" -ne 0 ]
  [ ! -d "$wt_dir" ]
}
