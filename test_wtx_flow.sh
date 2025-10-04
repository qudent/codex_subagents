#!/usr/bin/env bash
set -euo pipefail

# Comprehensive wtx test script: flow, inter-agent comms, isolation, recursion
# All test data is under testing-data/, nothing outside is touched.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_ROOT="$SCRIPT_DIR/testing-data/test-repo"
WORKTREES="$SCRIPT_DIR/testing-data"
REPO_NAME="test-repo"
WTX_SCRIPT="$SCRIPT_DIR/wtx"
export WTX_OSA_OPEN=0              # Disable macOS Terminal opening for tests
export WTX_SESSION_PREFIX="wtx_test"  # Avoid collisions with real sessions
export WTX_CONTAINER_DEFAULT="$WORKTREES"  # Direct worktrees into testing-data

fail()    { echo -e "\n❌ FAIL: $*"; exit 1; }
step()    { echo -e "\n👉 $*"; }
success() { echo -e "\n✅ $*"; }

# Helpers
meta_file() { echo "$TEST_ROOT/.git/wtx.meta/$1.env"; }
session_for() { echo "${WTX_SESSION_PREFIX}:$1"; }
tmux_safe_session() { echo "${1//:/_}"; }
tmux_has() { tmux has-session -t "$(tmux_safe_session "$1")" >/dev/null 2>&1; }
assert_contains() { local file="$1" pat="$2"; grep -E "$pat" "$file" >/dev/null || fail "pattern '$pat' not found in $file"; }
wait_for_file() {
  local file="$1" attempts="${2:-20}" delay="${3:-0.1}"
  local i
  for ((i=0; i<attempts; i++)); do
    [[ -f "$file" ]] && return 0
    sleep "$delay"
  done
  return 1
}

cleanup() {
  step "Cleaning up test repo and worktrees"
  rm -rf "$TEST_ROOT"
  if [ -d "$WORKTREES" ]; then
    # Remove all sNNN-* worktrees we might have created
    find "$WORKTREES" -maxdepth 1 -type d -name 's*' -exec rm -rf {} +
    rm -rf "$WORKTREES/${REPO_NAME}.worktrees"
  fi
}
trap cleanup EXIT

cleanup

step "Creating sandbox git repo at $TEST_ROOT"
mkdir -p "$TEST_ROOT"
cd "$TEST_ROOT"
git init -b main
git config user.email "test@example.com"
git config user.name "WTX Tester"
echo "# Test" > README.md
git add README.md
git commit -m "Initialize sandbox repo for wtx tests: add README for clarity"

# Sanity: default parent should be current branch (main here)
step "Default parent = current branch (on main)"
"$WTX_SCRIPT" create -d "default-main" --no-open | tee create_default_main.out
DEF_MAIN_BRANCH=$(sed -n 's/^OK: branch=\([^ ]*\).*/\1/p' create_default_main.out)
[ -n "${DEF_MAIN_BRANCH:-}" ] || fail "Could not parse default-main branch from wtx output"
[ -f "$(meta_file "$DEF_MAIN_BRANCH")" ] || fail "No meta for default-main"
assert_contains "$(meta_file "$DEF_MAIN_BRANCH")" "^PARENT_BRANCH=main$"
"$WTX_SCRIPT" remove --force "$DEF_MAIN_BRANCH" || fail "remove default-main failed"

# 1) Create parent
desc_parent="alpha"
step "Creating parent worktree: wtx create -d '$desc_parent' --no-open"
"$WTX_SCRIPT" create -d "$desc_parent" --no-open | tee create_parent.out
PARENT_BRANCH=$(sed -n 's/^OK: branch=\([^ ]*\).*/\1/p' create_parent.out)
[ -n "${PARENT_BRANCH:-}" ] || fail "Could not parse parent branch from wtx output"
PARENT_WT="$WORKTREES/$PARENT_BRANCH"
[ -d "$PARENT_WT" ] || fail "Parent worktree not created"

step "Verifying metadata for parent"
[ -f "$(meta_file "$PARENT_BRANCH")" ] || fail "No meta file for parent"
assert_contains "$(meta_file "$PARENT_BRANCH")" "^BRANCH=$PARENT_BRANCH$"
assert_contains "$(meta_file "$PARENT_BRANCH")" "^PARENT_BRANCH=main$"

step "wtx list shows parent worktree"
"$WTX_SCRIPT" list | grep -q "${PARENT_WT}" || fail "Parent worktree not listed"

step "env-setup inside parent"
cd "$PARENT_WT"
"$WTX_SCRIPT" env-setup | grep -q "env ready: BRANCH=$PARENT_BRANCH PARENT_BRANCH=main" || fail "env-setup output mismatch in parent"

# Sanity: switch repo to a non-main branch and ensure default parent follows
cd "$TEST_ROOT"
git checkout -b dev
echo "dev file" > dev.txt
git add dev.txt
git commit -m "Create dev branch with a file to verify default parent behavior on non-main"
step "Default parent = current branch (on dev)"
"$WTX_SCRIPT" create -d "default-dev" --no-open | tee create_default_dev.out
DEF_DEV_BRANCH=$(sed -n 's/^OK: branch=\([^ ]*\).*/\1/p' create_default_dev.out)
[ -n "${DEF_DEV_BRANCH:-}" ] || fail "Could not parse default-dev branch from wtx output"
DEF_DEV_META="$(meta_file "$DEF_DEV_BRANCH")"
[ -f "$DEF_DEV_META" ] || fail "No meta for default-dev"
assert_contains "$DEF_DEV_META" "^PARENT_BRANCH=dev$"
DEF_DEV_WT="$WORKTREES/$DEF_DEV_BRANCH"
[ -d "$DEF_DEV_WT" ] || fail "default-dev worktree not created"
"$WTX_SCRIPT" remove --force "$DEF_DEV_BRANCH" || fail "remove default-dev failed"

# Return to the parent worktree before testing open/session behavior
cd "$PARENT_WT"

step "open parent session and verify tmux session exists"
"$WTX_SCRIPT" open || fail "open failed for parent"
PARENT_SESSION="$(session_for "$PARENT_BRANCH")"
tmux_has "$PARENT_SESSION" || fail "tmux session not present for parent: $PARENT_SESSION"

# 2) Create child and grandchild
cd "$TEST_ROOT"
desc_child="beta"
step "Creating child of $PARENT_BRANCH"
"$WTX_SCRIPT" create -p "$PARENT_BRANCH" -d "$desc_child" --no-open | tee create_child.out
CHILD_BRANCH=$(sed -n 's/^OK: branch=\([^ ]*\).*/\1/p' create_child.out)
[ -n "${CHILD_BRANCH:-}" ] || fail "Could not parse child branch from wtx output"
CHILD_WT="$WORKTREES/$CHILD_BRANCH"
[ -d "$CHILD_WT" ] || fail "Child worktree not created"

desc_grand="gamma"
step "Creating grandchild of $CHILD_BRANCH"
"$WTX_SCRIPT" create -p "$CHILD_BRANCH" -d "$desc_grand" --no-open | tee create_grand.out
GRAND_BRANCH=$(sed -n 's/^OK: branch=\([^ ]*\).*/\1/p' create_grand.out)
[ -n "${GRAND_BRANCH:-}" ] || fail "Could not parse grandchild branch from wtx output"
GRAND_WT="$WORKTREES/$GRAND_BRANCH"
[ -d "$GRAND_WT" ] || fail "Grandchild worktree not created"

step "env-setup in child and grandchild uses correct PARENT_BRANCH"
cd "$CHILD_WT" && "$WTX_SCRIPT" env-setup | grep -q "PARENT_BRANCH=$PARENT_BRANCH" || fail "child PARENT_BRANCH not set correctly"
cd "$GRAND_WT" && "$WTX_SCRIPT" env-setup | grep -q "PARENT_BRANCH=$CHILD_BRANCH" || fail "grandchild PARENT_BRANCH not set correctly"

# 3) Inter-agent communication via tmux
PARENT_SESSION="$(session_for "$PARENT_BRANCH")"
CHILD_SESSION="$(session_for "$CHILD_BRANCH")"
GRAND_SESSION="$(session_for "$GRAND_BRANCH")"

step "Ensure sessions exist for all branches"
for s in "$PARENT_SESSION" "$CHILD_SESSION" "$GRAND_SESSION"; do tmux_has "$s" || fail "missing tmux session $s"; done

step "Child -> Parent via notify_parents --keys (writes to parent's log)"
cd "$CHILD_WT"
"$WTX_SCRIPT" notify_parents --keys "printf 'child->parent\n' >> wtx_msgs.log" || fail "notify_parents from child failed"
wait_for_file "$PARENT_WT/wtx_msgs.log" 30 0.1 || fail "Parent log not created by child notification"
grep -q "child->parent" "$PARENT_WT/wtx_msgs.log" || fail "Parent did not receive child's message"

step "Parent -> Child via notify_children --keys (writes to child's log)"
cd "$PARENT_WT"
"$WTX_SCRIPT" notify_children --keys "printf 'parent->child\n' >> wtx_msgs.log" || fail "notify_children from parent failed"
wait_for_file "$CHILD_WT/wtx_msgs.log" 30 0.1 || fail "Child log not created by parent notification"
grep -q "parent->child" "$CHILD_WT/wtx_msgs.log" || fail "Child did not receive parent's message"

step "Child -> Grandchild via notify_children --keys"
cd "$CHILD_WT"
"$WTX_SCRIPT" notify_children --keys "printf 'child->grand\n' >> wtx_msgs.log" || fail "notify_children from child failed"
wait_for_file "$GRAND_WT/wtx_msgs.log" 30 0.1 || fail "Grandchild log not created by child notification"
grep -q "child->grand" "$GRAND_WT/wtx_msgs.log" || fail "Grandchild did not receive child's message"

step "Grandchild notify_children reports no targets"
cd "$GRAND_WT"
"$WTX_SCRIPT" notify_children "noop" | grep -q "no target sessions found" || fail "Expected 'no target sessions found' for grandchild"

# 4) Isolation between worktrees
step "Isolation: create file only in child; verify not in parent"
cd "$CHILD_WT"
echo "child only" > only_in_child.txt
git add only_in_child.txt
git commit -m "Child branch: add only_in_child.txt to verify isolation across worktrees"
[ ! -f "$PARENT_WT/only_in_child.txt" ] || fail "Isolation breach: file appeared in parent"

step "Isolation: commit in child is not present in parent"
cd "$PARENT_WT"
! git ls-files --error-unmatch only_in_child.txt >/dev/null 2>&1 || fail "Parent sees child's tracked file unexpectedly"

# 5) Remove in reverse order and verify cleanup
cd "$TEST_ROOT"
step "Remove grandchild worktree"
"$WTX_SCRIPT" remove --force "$GRAND_BRANCH" || fail "remove grandchild failed"
[ ! -d "$GRAND_WT" ] || fail "Grandchild worktree not removed"
[ ! -f "$(meta_file "$GRAND_BRANCH")" ] || fail "Grandchild meta file still present"

step "Remove child worktree"
"$WTX_SCRIPT" remove --force "$CHILD_BRANCH" || fail "remove child failed"
[ ! -d "$CHILD_WT" ] || fail "Child worktree not removed"
[ ! -f "$(meta_file "$CHILD_BRANCH")" ] || fail "Child meta file still present"

step "Remove parent worktree"
"$WTX_SCRIPT" remove --force "$PARENT_BRANCH" || fail "remove parent failed"
[ ! -d "$PARENT_WT" ] || fail "Parent worktree not removed"
[ ! -f "$(meta_file "$PARENT_BRANCH")" ] || fail "Parent meta file still present"

success "All wtx tests passed: flow, inter-agent communication, isolation, recursion"
