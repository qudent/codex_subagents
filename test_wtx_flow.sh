#!/usr/bin/env bash
set -euo pipefail

# Comprehensive wtx test script for codex_subagents
# All test data is under testing-data/, nothing outside is touched.

TEST_ROOT="testing-data/test-repo"
WORKTREES="testing-data"
REPO_NAME="test-repo"
WTX_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/wtx"
export WTX_OSA_OPEN=0  # Disable macOS Terminal opening for tests
export WTX_SESSION_PREFIX="wtx_test"  # Avoid collisions with real sessions

fail()    { echo -e "\n❌ FAIL: $*"; exit 1; }
step()    { echo -e "\n👉 $*"; }
success() { echo -e "\n✅ $*"; }

cleanup() {
  step "Cleaning up test repo and worktrees"
  rm -rf "$TEST_ROOT"
  # Remove all worktrees created by this test
  find "$WORKTREES" -maxdepth 1 -type d -name 's*-main-*' -exec rm -rf {} +
  # Remove any old testrepo.worktrees or similar
  rm -rf "$WORKTREES/testrepo.worktrees" "$WORKTREES/wtx_testrepo.worktrees"
}
trap cleanup EXIT

cleanup

step "Creating sandbox git repo at $TEST_ROOT"
mkdir -p "$TEST_ROOT"
cd "$TEST_ROOT"
git init -b main
touch README.md
git add README.md
git commit -m "init"
git remote add origin .

desc="login feature"
step "Running: wtx create -d '$desc' --no-open"
"$WTX_SCRIPT" create -d "$desc" --no-open || fail "wtx create failed"

step "Verifying worktree creation"
BRANCH=$(ls "$WORKTREES" | grep s001-main-login)
WTREE="$WORKTREES/$BRANCH"
[ -d "$WTREE" ] || fail "Worktree not created"

step "Running: wtx list"
"$WTX_SCRIPT" list | grep -q "$WTREE" || fail "Worktree not listed"

step "Testing env-setup in worktree"
cd "$WTREE"
"$WTX_SCRIPT" env-setup | grep -q "env ready" || fail "env-setup failed"

step "Testing open (should not error, but won't open terminal)"
"$WTX_SCRIPT" open || fail "open failed"

step "Testing notify_parents and notify_children"
"$WTX_SCRIPT" notify_parents "Test message to parent" || fail "notify_parents failed"
"$WTX_SCRIPT" notify_children "Test message to children" || fail "notify_children failed"

step "Testing remove"
cd "$TEST_ROOT"
"$WTX_SCRIPT" remove "$BRANCH" || fail "remove failed"

step "Verifying worktree removal"
[ ! -d "$WTREE" ] || fail "Worktree not removed"

success "All wtx flow tests passed!"