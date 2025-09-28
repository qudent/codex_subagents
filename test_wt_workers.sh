#!/bin/sh
# test_wt_workers.sh
# Instructive test setup for wt_workers_clear.sh
# Demonstrates repo setup, worker spawning, tmux interaction, merging, cleanup, and edge cases.

# Record root dir to clean up properly later
ROOT_DIR=$(pwd -P)

# Helper: resolve the worktree path for the newest worker branch with the given prefix
find_worker_worktree() {
  prefix="$1"
  git worktree list --porcelain | awk -v prefix="$prefix" '
    $1=="worktree" { wt=$2; next }
    $1=="branch" {
      ref=$2
      sub("^refs/heads/", "", ref)
      if (index(ref, prefix) == 1) {
        print wt
        exit
      }
    }
  '
}

# 1. Source the script
. worktree-subagent-automation.sh

echo "✅ Sourced worktree-subagent-automation.sh"


# 2. Create a temporary test directory and initialize a git repo
TESTDIR="test"
mkdir -p "$TESTDIR"
cd "$TESTDIR" || exit 1
echo "# Test Repo" > README.md
git init
git add README.md
git commit -m "init"

echo "✅ Created test repo at $TESTDIR"

# 3. Create a dummy file and commit to main
cat <<EOF > hello.txt
Hello from main branch!
EOF
git add hello.txt
git commit -m "Add hello.txt"

echo "✅ Added hello.txt to main"

# 4. Spawn a worker (worktree + tmux session)
short="testworker"
spinup_worker "$short" main

echo "✅ Spawned worker '$short'"

# 5. Send instructions to tmux to create a file in the worker
# Find the session name and worktree path via git worktree metadata
worker_prefix="worker/${short}-"
wt_path="$(find_worker_worktree "$worker_prefix")"
if [ -z "$wt_path" ]; then
  echo "❌ Failed to locate worktree for $short" >&2
  exit 1
fi
session="$(basename "$wt_path")"

# Create a file in the tmux session
TMUX_CMD='echo "Created from tmux" > tmuxfile.txt'
tmux send-keys -t "$session:0.0" "$TMUX_CMD" C-m
sleep 1  # Give tmux time to create the file

# 6. Commit the new file in the worker
(cd "$wt_path" && git add tmuxfile.txt && git commit -m "Add tmuxfile.txt from tmux")
echo "✅ tmuxfile.txt created and committed in worker"

# 7. Merge changes back to main (with and without quitting tmux)
merge_worker "$wt_path" --target main --ff-only
echo "✅ Merged worker changes into main"

# 8. Test cleanup: kill tmux, remove worktree, delete branch
finish_worker "$wt_path" --target main --ff-only

echo "✅ Finished worker and cleaned up"

# 9. Edge case: dirty worktree, force cleanup, dry-run, prune branches
spinup_worker dirtyworker main
dirty_prefix="worker/dirtyworker-"
wt_path_dirty="$(find_worker_worktree "$dirty_prefix")"
if [ -z "$wt_path_dirty" ]; then
  echo "❌ Failed to locate worktree for dirtyworker" >&2
  exit 1
fi
echo "Uncommitted change" > "$wt_path_dirty/dirty.txt"

# Try to finish worker (should fail)
finish_worker "$wt_path_dirty" --target main --ff-only || echo "Expected failure: dirty worktree"

# Force cleanup
finish_worker "$wt_path_dirty" --target main --ff-only --force
echo "✅ Forced cleanup of dirty worker"

# Dry-run cleanup
clean_worktrees --dry-run

echo "✅ Dry-run cleanup complete"

# Prune stray branches
clean_worktrees --prune-branches

echo "✅ Pruned stray branches"

# Cleanup test repo
tmux kill-server || true
cd "$ROOT_DIR"
rm -rf "$TESTDIR"
echo "✅ Test complete and cleaned up"

# --- End of test script ---

# To run:
#   sh test_wt_workers.sh
# Make sure you have tmux and git installed, and the script path is correct.
# This script demonstrates the main features and edge cases of wt_workers_clear.sh.
