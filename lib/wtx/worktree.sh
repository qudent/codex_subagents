# shellcheck shell=bash

wtx::determine_parent_branch() {
  PARENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo detached)
  PARENT_SHA=$(git rev-parse "$FROM_REF")
  PARENT_SHORT=$(git rev-parse --short "$PARENT_SHA")
}

wtx::acquire_number_lock() {
  local branch="$1"
  local lock_key
  lock_key=$(wtx::sanitize_name "$branch")
  WTX_LOCKDIR="$WTX_GIT_DIR_ABS/locks/${lock_key}.lockdir"
  while ! mkdir "$WTX_LOCKDIR" 2>/dev/null; do
    if [ -d "$WTX_LOCKDIR" ]; then
      local stale_age
      stale_age=$(python - "$WTX_LOCKDIR" <<'PY'
import os
import sys
import time

lock_path = sys.argv[1]
if not os.path.exists(lock_path):
    raise SystemExit(0)
age = time.time() - os.stat(lock_path).st_mtime
if age >= 30:
    print(int(age))
PY
)
      if [ -n "$stale_age" ]; then
        printf '[wtx] stale numbering lock for %s (age %ss); stealing.\n' "$branch" "$stale_age" >&2
        rm -rf "$WTX_LOCKDIR"
        continue
      fi
    fi
    sleep 0.05
  done
  trap wtx::release_number_lock EXIT
}

wtx::release_number_lock() {
  if [ -n "${WTX_LOCKDIR:-}" ]; then
    rmdir "$WTX_LOCKDIR" 2>/dev/null || true
  fi
}

wtx::select_branch_name() {
  if [ -n "$NAME" ]; then
    BRANCH_NAME="$NAME"
    return
  fi
  local existing last
  existing=$(git for-each-ref --format='%(refname:short)' "refs/heads/wtx/${PARENT_BRANCH}-*" 2>/dev/null | \
    grep -E "^wtx/${PARENT_BRANCH}-[0-9]+$" || true)
  last=$(printf '%s\n' "$existing" | sed -E 's/.*-([0-9]+)$/\1/' | sort -n | tail -1 || printf '0')
  if [ -z "$last" ]; then
    NN=1
  else
    NN=$(( last + 1 ))
  fi
  BRANCH_NAME="wtx/${PARENT_BRANCH}-${NN}"
}

wtx::prepare_branch_state() {
  WORKTREE_NAME=$(wtx::sanitize_name "$BRANCH_NAME")
  READY_FILE="$WT_STATE_DIR/$WORKTREE_NAME.ready"
  rm -f "$READY_FILE" 2>/dev/null || true
}

wtx::ensure_branch_exists() {
  if ! git show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
    git branch "$BRANCH_NAME" "$FROM_REF" 2>/dev/null || \
      git branch --no-track "$BRANCH_NAME" "$FROM_REF"
  fi
}

wtx::record_branch_metadata() {
  local desc
  desc="wtx: created_by=wtx\nwtx: parent_branch=${PARENT_BRANCH}\nwtx: from_ref=${FROM_REF}"
  git config "branch.$BRANCH_NAME.description" "$desc" >/dev/null 2>&1 || true
  local state_json tmp_json
  state_json="$WT_STATE_DIR/$WORKTREE_NAME.json"
  tmp_json=$(mktemp "$WTX_GIT_DIR_ABS/tmp.state.XXXXXX")
  printf '{"created_by":"wtx","branch":"%s","parent_branch":"%s","from_ref":"%s"}\n' \
    "$BRANCH_NAME" "$PARENT_BRANCH" "$FROM_REF" >"$tmp_json"
  mv "$tmp_json" "$state_json"
}

wtx::ensure_worktree_root() {
  WORKTREE_ROOT="$(dirname "$REPO_ROOT")/${REPO_BASENAME}.worktrees"
  WT_DIR="$WORKTREE_ROOT/$WORKTREE_NAME"
  mkdir -p "$WORKTREE_ROOT"
}

wtx::prune_stale_worktree() {
  if [ -d "$WT_DIR" ] && ! git -C "$REPO_ROOT" worktree list --porcelain | grep -q "worktree $WT_DIR"; then
    git -C "$REPO_ROOT" worktree prune || true
  fi
}

wtx::ensure_worktree_present() {
  WORKTREE_STATUS="reused"
  if ! git -C "$REPO_ROOT" worktree list --porcelain | grep -q "worktree $WT_DIR"; then
    git -C "$REPO_ROOT" worktree add "$WT_DIR" "$BRANCH_NAME"
    WORKTREE_STATUS="created"
  fi
}

wtx::ensure_uv_env() {
  ENV_STATUS="missing"
  if [ -z "$WTX_UV_ENV" ]; then
    ENV_STATUS="skipped"
    return
  fi
  if ! need uv; then
    return
  fi
  mkdir -p "$(dirname "$WTX_UV_ENV")"
  if [ -d "$WTX_UV_ENV/bin" ]; then
    ENV_STATUS="reused"
  else
    uv venv "$WTX_UV_ENV"
    ENV_STATUS="created"
  fi
}

wtx::ensure_pnpm() {
  PNPM_STATUS="skipped"
  if [ ! -f "$WT_DIR/package.json" ]; then
    return
  fi
  if ! need pnpm; then
    PNPM_STATUS="missing"
    return
  fi
  PNPM_STATUS="reused"
  local stamp="$WT_DIR/.wtx_pnpm_stamp"
  if [ ! -d "$WT_DIR/node_modules" ] || { [ -f "$WT_DIR/pnpm-lock.yaml" ] && [ "$WT_DIR/pnpm-lock.yaml" -nt "$stamp" ]; }; then
    (
      cd "$WT_DIR"
      pnpm install --frozen-lockfile
    )
    local tmp_stamp
    tmp_stamp=$(mktemp "$WT_DIR/.wtx_pnpm.XXXXXX")
    date +%s >"$tmp_stamp"
    mv "$tmp_stamp" "$stamp"
    PNPM_STATUS="created"
  fi
}
