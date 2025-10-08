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
  export HOME="$TEST_ROOT/home" WTX_UV_ENV="$HOME/.wtx/uv-shared"
  mkdir -p "$HOME"
  unset TMUX
}

teardown() {
  tmux kill-server >/dev/null 2>&1 || true
  if screen -ls >/dev/null 2>&1; then
    screen -ls | awk '/\t/ {print $1}' | while read -r ses; do
      screen -S "$ses" -X quit >/dev/null 2>&1 || true
    done
  fi
  rm -rf "$TEST_ROOT"
}

wtx() {
  (cd "$REPO_ROOT" && "$BATS_TEST_DIRNAME/../wtx" "$@")
}

sanitize() { printf '%s' "$1" | tr '/:' '__'; }

list_wtx_branches() {
  git -C "$REPO_ROOT" for-each-ref --format='%(refname:short)' 'refs/heads/wtx/**' | sort
}

first_new_branch() {
  before="$1"; after="$2"
  OLDIFS="$IFS"; IFS=$'\n'
  for candidate in $after; do
    [ -n "$candidate" ] || continue
    found=0
    for existing in $before; do
      [ "$candidate" = "$existing" ] && { found=1; break; }
    done
    if [ $found -eq 0 ]; then
      printf '%s' "$candidate"
      IFS="$OLDIFS"
      return
    fi
  done
  IFS="$OLDIFS"
}

worktree_path() {
  printf '%s/%s.worktrees/%s' "$(dirname "$REPO_ROOT")" "$(basename "$REPO_ROOT")" "$(sanitize "$1")"
}

session_name() {
  branch="$1"
  base_repo="$(sanitize "$(basename "$REPO_ROOT")")"
  parent="$(branch_parent "$branch")"
  if [ -n "$parent" ]; then
    parent_path="$(actual_worktree_path "$parent")"
    if [ -d "$parent_path" ]; then
      base_repo="$(sanitize "$(basename "$parent_path")")"
    fi
  fi
  printf 'wtx_%s_%s' "$base_repo" "$(sanitize "$branch")"
}

branch_parent() {
  state_file="$REPO_ROOT/.git/wtx/state/$(sanitize "$1").json"
  if [ -f "$state_file" ]; then
    parent=$(sed -n 's/.*"parent_branch":"\([^"]*\)".*/\1/p' "$state_file" | head -n 1)
    if [ -n "$parent" ]; then
      printf '%s\n' "$parent"
      return
    fi
  fi
  desc=$(git -C "$REPO_ROOT" config --get "branch.$1.description" 2>/dev/null || true)
  printf '%s\n' "$desc" | sed -n 's/^wtx: parent_branch=//p' | head -n 1
}

actual_worktree_path() {
  branch="$1"
  candidate="$(worktree_path "$branch")"
  if [ -d "$candidate" ]; then
    printf '%s' "$candidate"
    return
  fi
  parent="$(branch_parent "$branch")"
  if [ -z "$parent" ]; then
    printf '%s' "$candidate"
    return
  fi
  parent_path="$(actual_worktree_path "$parent")"
  printf '%s/%s.worktrees/%s' "$(dirname "$parent_path")" "$(basename "$parent_path")" "$(sanitize "$branch")"
}
