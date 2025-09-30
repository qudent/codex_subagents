#!/usr/bin/env bash
set -euo pipefail

# This script thoroughly tests the wtx flow in a sandboxed repo under testing/
# It does not touch files/folders outside testing/

TEST_ROOT="testing/wtx_testrepo"
WORKTREES="testing/wtx_testrepo.worktrees"
REPO_NAME="wtx_testrepo"
WTX_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/wtx"
export WTX_OSA_OPEN=0  # Disable macOS Terminal opening for tests
export WTX_SESSION_PREFIX="wtx_test"  # Avoid collisions with real sessions

fail() { echo "FAIL: $*"; exit 1; }

step() { echo "\n==> $*"; }

cleanup() {
  step "Cleaning up test repo and worktrees"
  rm -rf "$TEST_ROOT" "$WORKTREES"
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
"$WTX_SCRIPT" create -d "$desc" --no-open

step "Verifying worktree creation"
ls "$WORKTREES" | grep -q s001-main-login || fail "Worktree not created"

BRANCH=$(ls "$WORKTREES" | grep s001-main-login)
WTREE="$WORKTREES/$BRANCH"

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

step "All wtx flow tests passed!"
