#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_ROOT="$SCRIPT_DIR/testing-data/test-repo"
CONTAINER_ROOT="$SCRIPT_DIR/testing-data"
WTX_SCRIPT="$SCRIPT_DIR/wtx"
REPO_NAME="test-repo"
WORKTREE_PARENT="$CONTAINER_ROOT"

export WTX_CONTAINER_DEFAULT="$CONTAINER_ROOT"
export WTX_MESSAGING_POLICY="all"

fail(){ echo "\n❌ FAIL: $*"; exit 1; }
step(){ echo "\n👉 $*"; }
success(){ echo "\n✅ $*"; }
wait_for_file(){ local path="$1" timeout="${2:-30}"; for ((i=0;i<timeout;i++)); do [[ -f "$path" ]] && return 0; sleep 1; done; return 1; }
session_name(){ local branch="$1"; local combined="${REPO_NAME}-${branch}"; echo "${combined//[^A-Za-z0-9._-]/-}"; }
tmux_has(){ tmux has-session -t "$1" >/dev/null 2>&1; }
wait_for_session(){ local name="$1"; for ((i=0;i<40;i++)); do tmux_has "$name" && return 0; sleep 0.2; done; return 1; }
kill_test_sessions(){
  local sessions
  sessions=$(tmux list-sessions -F '#{session_name}' 2>/dev/null || true)
  if [[ -n "$sessions" ]]; then
    while read -r name; do
      [[ "$name" == ${REPO_NAME}-* ]] && tmux kill-session -t "$name" >/dev/null 2>&1 || true
    done <<<"$sessions"
  fi
}

cleanup(){ step "Cleaning test artifacts"; kill_test_sessions; rm -rf "$TEST_ROOT" "$WORKTREE_PARENT"; }
trap cleanup EXIT

cleanup

step "Initialize sandbox repository"
mkdir -p "$TEST_ROOT"
cd "$TEST_ROOT"
git init -b main >/dev/null
git config user.email "tester@example.com"
git config user.name "WTX Tester"
echo "# Sandbox" > README.md
git add README.md
git commit -m "Initial sandbox commit for wtx tests" >/dev/null
mkdir -p .venv/bin
touch .venv/bin/activate

# ---------------------------------------------------------------------------
# Default parent selection (main)
# ---------------------------------------------------------------------------
step "Default parent is the active branch (main)"
DEFAULT_MAIN_OUT="$($WTX_SCRIPT create)"
echo "$DEFAULT_MAIN_OUT" | grep -q "created branch=" || fail "create output missing expected prefix"
DEFAULT_MAIN_BRANCH="$(echo "$DEFAULT_MAIN_OUT" | sed -n 's/^created branch=\([^ ]*\) .*/\1/p')"
DEFAULT_MAIN_WT="$(echo "$DEFAULT_MAIN_OUT" | sed -n 's/.* worktree=\([^ ]*\) .*/\1/p')"
[[ -d "$DEFAULT_MAIN_WT" ]] || fail "main default worktree missing"
git config --get "branch.$DEFAULT_MAIN_BRANCH.description" | grep -q "parent=main" || fail "main default branch missing parent description"
DEFAULT_MAIN_SESSION="$(session_name "$DEFAULT_MAIN_BRANCH")"
wait_for_session "$DEFAULT_MAIN_SESSION" || fail "main default tmux session missing"
tmux kill-session -t "$DEFAULT_MAIN_SESSION" >/dev/null 2>&1 || true
git worktree remove -f "$DEFAULT_MAIN_WT" >/dev/null
git branch -D "$DEFAULT_MAIN_BRANCH" >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# Default parent selection (non-main)
# ---------------------------------------------------------------------------
step "Default parent follows current branch (dev)"
git checkout -b dev >/dev/null
DEFAULT_DEV_OUT="$($WTX_SCRIPT create)"
DEFAULT_DEV_BRANCH="$(echo "$DEFAULT_DEV_OUT" | sed -n 's/^created branch=\([^ ]*\) .*/\1/p')"
DEFAULT_DEV_WT="$(echo "$DEFAULT_DEV_OUT" | sed -n 's/.* worktree=\([^ ]*\) .*/\1/p')"
[[ -d "$DEFAULT_DEV_WT" ]] || fail "dev default worktree missing"
git config --get "branch.$DEFAULT_DEV_BRANCH.description" | grep -q "parent=dev" || fail "dev default branch missing parent description"
DEFAULT_DEV_SESSION="$(session_name "$DEFAULT_DEV_BRANCH")"
wait_for_session "$DEFAULT_DEV_SESSION" || fail "dev default tmux session missing"
tmux kill-session -t "$DEFAULT_DEV_SESSION" >/dev/null 2>&1 || true
git worktree remove -f "$DEFAULT_DEV_WT" >/dev/null
git branch -D "$DEFAULT_DEV_BRANCH" >/dev/null 2>&1 || true
git checkout main >/dev/null
git branch -D dev >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# Create multi-generation hierarchy
# ---------------------------------------------------------------------------
declare PARENT_BRANCH="" PARENT_WT="" PARENT_SESSION=""
declare CHILD_BRANCH="" CHILD_WT="" CHILD_SESSION=""
declare GRAND_BRANCH="" GRAND_WT="" GRAND_SESSION=""

step "Create parent agent worktree with startup hook"
PARENT_OUT="$($WTX_SCRIPT create parent-agent -c "printf 'parent-ready\n' >> ready.log")"
PARENT_BRANCH="$(echo "$PARENT_OUT" | sed -n 's/^created branch=\([^ ]*\) .*/\1/p')"
PARENT_WT="$(echo "$PARENT_OUT" | sed -n 's/.* worktree=\([^ ]*\) .*/\1/p')"
[[ -d "$PARENT_WT" ]] || fail "Parent worktree missing"
[[ -L "$PARENT_WT/.venv" ]] || fail "Parent missing .venv symlink"
[[ "$(readlink "$PARENT_WT/.venv")" == "$TEST_ROOT/.venv" ]] || fail ".venv symlink target incorrect"
git config --get "branch.$PARENT_BRANCH.description" | grep -q "parent=main" || fail "Parent branch missing parent=main description"
PARENT_SESSION="$(session_name "$PARENT_BRANCH")"
wait_for_session "$PARENT_SESSION" || fail "Parent tmux session missing"
HOOK_PATH=$(git -C "$PARENT_WT" rev-parse --git-path hooks/post-commit)
[[ -x "$HOOK_PATH" ]] || fail "post-commit hook not installed"
wait_for_file "$PARENT_WT/ready.log" 10 || fail "Parent startup command did not execute"

step "Create child agent using parent worktree"
cd "$PARENT_WT"
CHILD_OUT="$($WTX_SCRIPT create child-agent)"
CHILD_BRANCH="$(echo "$CHILD_OUT" | sed -n 's/^created branch=\([^ ]*\) .*/\1/p')"
CHILD_WT="$(echo "$CHILD_OUT" | sed -n 's/.* worktree=\([^ ]*\) .*/\1/p')"
[[ -d "$CHILD_WT" ]] || fail "Child worktree missing"
git config --get "branch.$CHILD_BRANCH.description" | grep -q "parent=$PARENT_BRANCH" || fail "Child missing parent description"
[[ -L "$CHILD_WT/.venv" ]] || fail "Child missing .venv symlink"
CHILD_SESSION="$(session_name "$CHILD_BRANCH")"
wait_for_session "$CHILD_SESSION" || fail "Child tmux session missing"

step "Create grandchild agent from child worktree"
cd "$CHILD_WT"
GRAND_OUT="$($WTX_SCRIPT create grand-agent)"
GRAND_BRANCH="$(echo "$GRAND_OUT" | sed -n 's/^created branch=\([^ ]*\) .*/\1/p')"
GRAND_WT="$(echo "$GRAND_OUT" | sed -n 's/.* worktree=\([^ ]*\) .*/\1/p')"
[[ -d "$GRAND_WT" ]] || fail "Grandchild worktree missing"
git config --get "branch.$GRAND_BRANCH.description" | grep -q "parent=$CHILD_BRANCH" || fail "Grandchild missing parent description"
GRAND_SESSION="$(session_name "$GRAND_BRANCH")"
wait_for_session "$GRAND_SESSION" || fail "Grandchild tmux session missing"

step "wtx list shows hierarchy"
LIST_OUTPUT="$($WTX_SCRIPT list)"
echo "$LIST_OUTPUT" | grep -q "BRANCH" || fail "list header missing"
echo "$LIST_OUTPUT" | grep -q "$PARENT_BRANCH" || fail "Parent not listed"
echo "$LIST_OUTPUT" | grep -q "$CHILD_BRANCH" || fail "Child not listed"
echo "$LIST_OUTPUT" | grep -q "$GRAND_BRANCH" || fail "Grandchild not listed"
echo "$LIST_OUTPUT" | grep -Eq "${CHILD_BRANCH}[[:space:]]+${PARENT_BRANCH}" || fail "Child listing missing parent"
echo "$LIST_OUTPUT" | grep -Eq "${GRAND_BRANCH}[[:space:]]+${CHILD_BRANCH}" || fail "Grandchild listing missing parent"

# ---------------------------------------------------------------------------
# Messaging propagation across generations
# ---------------------------------------------------------------------------
step "Commit in parent notifies child"
cd "$PARENT_WT"
echo "parent-update" > parent.log
git add parent.log
git commit -m "Parent: seed child" >/dev/null
parent_hash=$(git rev-parse --short HEAD)
sleep 1
CHILD_CAPTURE="$(tmux capture-pane -t "$CHILD_SESSION" -p)"
echo "$CHILD_CAPTURE" | grep -q "# \[wtx from ${PARENT_BRANCH}\]:" || fail "Child session missing parent message"
echo "$CHILD_CAPTURE" | grep -q "git merge ${parent_hash}" || fail "Child message missing merge hint"

step "Commit in child notifies parent and grandchild"
cd "$CHILD_WT"
echo "child-only" > child.txt
git add child.txt
git commit -m "Child: broadcast to parent and grandchild" >/dev/null
child_hash=$(git rev-parse --short HEAD)
sleep 1
PARENT_CAPTURE="$(tmux capture-pane -t "$PARENT_SESSION" -p)"
echo "$PARENT_CAPTURE" | grep -q "# \[wtx from ${CHILD_BRANCH}\]:" || fail "Parent session missing child message"
echo "$PARENT_CAPTURE" | grep -q "git merge ${child_hash}" || fail "Parent message missing merge hint"
GRAND_CAPTURE="$(tmux capture-pane -t "$GRAND_SESSION" -p)"
echo "$GRAND_CAPTURE" | grep -q "# \[wtx from ${CHILD_BRANCH}\]:" || fail "Grandchild session missing child message"

step "Commit in grandchild notifies parent branch"
cd "$GRAND_WT"
echo "grand-only" > grand.txt
git add grand.txt
git commit -m "Grandchild: notify parent" >/dev/null
grand_hash=$(git rev-parse --short HEAD)
sleep 1
CHILD_CAPTURE_AFTER="$(tmux capture-pane -t "$CHILD_SESSION" -p)"
echo "$CHILD_CAPTURE_AFTER" | grep -q "# \[wtx from ${GRAND_BRANCH}\]:" || fail "Child session missing grandchild message"
echo "$CHILD_CAPTURE_AFTER" | grep -q "git merge ${grand_hash}" || fail "Grandchild message missing merge hint"

step "Explicit message with no children reports absence"
NO_TARGET_MSG="$(WTX_MESSAGING_POLICY=children "$WTX_SCRIPT" message 2>&1 || true)"
echo "$NO_TARGET_MSG" | grep -q "no messaging targets" || fail "Expected no target warning"

# ---------------------------------------------------------------------------
# Isolation between worktrees
# ---------------------------------------------------------------------------
step "Isolation: child artifact is absent from parent"
cd "$PARENT_WT"
[[ ! -f child.txt ]] || fail "Child file leaked into parent"
if git ls-files --error-unmatch child.txt >/dev/null 2>&1; then
  fail "Parent unexpectedly tracks child file"
fi

# ---------------------------------------------------------------------------
# Cleanup via git + prune
# ---------------------------------------------------------------------------
step "Manual worktree removal followed by wtx prune"
cd "$TEST_ROOT"
git worktree remove -f "$GRAND_WT" >/dev/null
git branch -D "$GRAND_BRANCH" >/dev/null 2>&1 || true
git worktree remove -f "$CHILD_WT" >/dev/null
git branch -D "$CHILD_BRANCH" >/dev/null 2>&1 || true
git worktree remove -f "$PARENT_WT" >/dev/null
git branch -D "$PARENT_BRANCH" >/dev/null 2>&1 || true
mkdir -p "$WORKTREE_PARENT/stale"
"$WTX_SCRIPT" prune >/dev/null
[[ ! -d "$GRAND_WT" ]] || fail "Grandchild worktree directory still present"
[[ ! -d "$CHILD_WT" ]] || fail "Child worktree directory still present"
[[ ! -d "$PARENT_WT" ]] || fail "Parent worktree directory still present"
[[ ! -d "$WORKTREE_PARENT/stale" ]] || fail "Prune failed to remove stale directory"
tmux_has "$GRAND_SESSION" && fail "Grandchild tmux session survived prune"
tmux_has "$CHILD_SESSION" && fail "Child tmux session survived prune"
tmux_has "$PARENT_SESSION" && fail "Parent tmux session survived prune"

success "wtx workflow tests completed"
