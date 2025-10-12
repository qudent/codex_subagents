# shellcheck shell=bash
wtx::init_repo_context() {
  REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
    echo "Not inside a git repo" >&2
    exit 1
  }
  GIT_DIR=$(git rev-parse --git-dir)
  GIT_COMMON_DIR=$(git rev-parse --git-common-dir)
  case "$GIT_COMMON_DIR" in
    /*) GIT_COMMON_DIR_ABS="$GIT_COMMON_DIR" ;;
    *) GIT_COMMON_DIR_ABS="$REPO_ROOT/$GIT_COMMON_DIR" ;;
  esac
  REPO_BASENAME=$(basename "$REPO_ROOT")
  DEFAULT_WTX_DIR="$GIT_COMMON_DIR_ABS/wtx"
  WTX_GIT_DIR=${WTX_GIT_DIR:-"$DEFAULT_WTX_DIR"}
  WTX_PROMPT=${WTX_PROMPT:-0}
  DEFAULT_UV_ENV="$GIT_COMMON_DIR_ABS/../.venv"
  WTX_UV_ENV=${WTX_UV_ENV:-"$DEFAULT_UV_ENV"}
  case "$WTX_GIT_DIR" in
    /*) WTX_GIT_DIR_ABS="$WTX_GIT_DIR" ;;
    *) WTX_GIT_DIR_ABS="$REPO_ROOT/$WTX_GIT_DIR" ;;
  esac
  if [ -n "$WTX_UV_ENV" ]; then
    case "$WTX_UV_ENV" in
      /*) : ;;
      *) WTX_UV_ENV="$REPO_ROOT/$WTX_UV_ENV" ;;
    esac
  fi

  mkdir -p "$WTX_GIT_DIR_ABS" "$WTX_GIT_DIR_ABS/logs" "$WTX_GIT_DIR_ABS/locks" "$WTX_GIT_DIR_ABS/state"
  local perm_stamp="$WTX_GIT_DIR_ABS/.perm_stamp"
  if [ ! -f "$perm_stamp" ]; then
    chmod 700 "$WTX_GIT_DIR_ABS" || true
    : >"$perm_stamp"
    printf '[wtx] secured permissions on %s\n' "$WTX_GIT_DIR_ABS" >&2
  fi

  WT_STATE_DIR="$WTX_GIT_DIR_ABS/state"
}

wtx::compute_repo_id() {
  local id_source="$GIT_COMMON_DIR_ABS"
  if need sha1sum; then
    REPO_ID=$(printf '%s' "$id_source" | sha1sum | awk '{print $1}' | cut -c1-8)
  else
    REPO_ID=$(printf '%s' "$id_source" | shasum -a 1 | awk '{print $1}' | cut -c1-8)
  fi
}

wtx::normalize_messaging_policy() {
  local raw="${WTX_MESSAGING_POLICY:-parent+children}"
  case "$raw" in
    parent|children|parent+children|all)
      MESSAGING_POLICY="$raw"
      ;;
    parent,children)
      MESSAGING_POLICY="parent+children"
      ;;
    "")
      MESSAGING_POLICY="parent+children"
      ;;
    *)
      printf 'Invalid WTX_MESSAGING_POLICY value: %s\n' "$raw" >&2
      exit 64
      ;;
  esac
}

wtx::resolve_messaging_targets() {
  local current_branch="$1"
  [ -d "$WT_STATE_DIR" ] || return 0
  python - "$WT_STATE_DIR" "$current_branch" "$MESSAGING_POLICY" <<'PY'
import json
import os
import sys
from collections import deque, defaultdict

state_dir, current_branch, policy = sys.argv[1:4]
parent_of = {}
children_of = defaultdict(set)

try:
    entries = os.listdir(state_dir)
except FileNotFoundError:
    entries = []

for name in entries:
    if not name.endswith('.json'):
        continue
    path = os.path.join(state_dir, name)
    try:
        with open(path, 'r', encoding='utf-8') as fh:
            data = json.load(fh)
    except Exception:
        continue
    branch = data.get('branch')
    parent = data.get('parent_branch')
    if not branch:
        continue
    parent_of[branch] = parent or ""
    if parent:
        children_of[parent].add(branch)

targets = set()

def add_parent(branch):
    parent = parent_of.get(branch)
    if parent:
        targets.add(parent)

def add_children(branch):
    for child in children_of.get(branch, []):
        targets.add(child)

if policy == 'parent':
    add_parent(current_branch)
elif policy == 'children':
    add_children(current_branch)
elif policy == 'parent+children':
    add_parent(current_branch)
    add_children(current_branch)
elif policy == 'all':
    seed = []
    parent = parent_of.get(current_branch)
    if parent:
        seed.append(parent)
    seed.extend(children_of.get(current_branch, []))
    visited = set([current_branch])
    queue = deque(seed)
    while queue:
        item = queue.popleft()
        if not item or item in visited:
            continue
        visited.add(item)
        targets.add(item)
        parent = parent_of.get(item)
        if parent:
            queue.append(parent)
        for child in children_of.get(item, []):
            queue.append(child)

for branch in sorted(targets):
    sys.stdout.write(branch + '\n')
PY
}

wtx::session_name_for_branch() {
  local branch="$1"
  printf 'wtx_%s_%s' "$(wtx::sanitize_name "$REPO_BASENAME")" "$(wtx::sanitize_name "$branch")"
}

wtx::session_pty_for_branch() {
  local branch="$1"
  printf '%s/sessions/%s.pty' "$WTX_GIT_DIR_ABS" "$(wtx::session_name_for_branch "$branch")"
}

wtx::session_pid_file_for_branch() {
  local branch="$1"
  printf '%s/sessions/%s.pid' "$WTX_GIT_DIR_ABS" "$(wtx::session_name_for_branch "$branch")"
}

wtx::session_running_for_branch() {
  local branch="$1"
  local pid_file
  pid_file=$(wtx::session_pid_file_for_branch "$branch")
  [ -f "$pid_file" ] || return 1
  local pid
  pid=$(cat "$pid_file" 2>/dev/null || true)
  if [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then
    return 1
  fi
  local pty
  pty=$(wtx::session_pty_for_branch "$branch")
  [ -e "$pty" ] || return 1
  return 0
}

wtx::send_branch_message() {
  local branch="$1"
  local payload="$2"
  if ! wtx::session_running_for_branch "$branch"; then
    return 1
  fi
  local pty
  pty=$(wtx::session_pty_for_branch "$branch")
  printf '%s\n' "$payload" | socat - "FILE:$pty,raw,echo=0" >/dev/null 2>&1
}

wtx::install_post_commit_hook() {
  local hook_dir="$GIT_DIR/hooks"
  local hook="$hook_dir/post-commit"
  local marker="# wtx post-commit hook"
  mkdir -p "$hook_dir"
  if [ -f "$hook" ]; then
    if grep -q "$marker" "$hook"; then
      chmod +x "$hook" 2>/dev/null || true
      return
    fi
    local tmp
    tmp=$(mktemp "$hook_dir/post-commit.XXXXXX")
    cat "$hook" >"$tmp"
    printf '\n%s\n' "$marker" >>"$tmp"
    cat >>"$tmp" <<'HOOK'
if command -v wtx >/dev/null 2>&1; then
  wtx --_post-commit || true
fi
HOOK
    mv "$tmp" "$hook"
    chmod +x "$hook" 2>/dev/null || true
    return
  fi
  local tmp
  tmp=$(mktemp "$hook_dir/post-commit.XXXXXX")
  cat >"$tmp" <<'HOOK'
#!/usr/bin/env bash
# wtx post-commit hook
if command -v wtx >/dev/null 2>&1; then
  wtx --_post-commit || true
fi
HOOK
  mv "$tmp" "$hook"
  chmod +x "$hook" 2>/dev/null || true
}

wtx::handle_post_commit() {
  wtx::normalize_messaging_policy
  if ! need socat; then
    return 0
  fi
  local branch
  branch=$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo detached)
  if [ "$branch" = "HEAD" ] || [ "$branch" = "detached" ]; then
    return 0
  fi
  local short_sha subject message targets filtered
  short_sha=$(git -C "$REPO_ROOT" log -1 --pretty=%h 2>/dev/null || true)
  subject=$(git -C "$REPO_ROOT" log -1 --pretty=%s 2>/dev/null || true)
  [ -n "$short_sha" ] || return 0
  message="# [wtx] $branch commit $short_sha \"$(wtx::sanitize_commit_payload "$subject")\""
  targets=$(wtx::resolve_messaging_targets "$branch")
  filtered=""
  if [ -n "$targets" ]; then
    while read -r target_branch; do
      [ -n "$target_branch" ] || continue
      [ "$target_branch" = "$branch" ] && continue
      if [ -z "$filtered" ]; then
        filtered="$target_branch"
      else
        filtered="$filtered\n$target_branch"
      fi
    done <<EOF
$targets
EOF
  fi
  if [ -n "$filtered" ]; then
    while read -r target_branch; do
      [ -n "$target_branch" ] || continue
      [ "$target_branch" = "$branch" ] && continue
      wtx::send_branch_message "$target_branch" "$message" || true
    done <<EOF
$filtered
EOF
  fi
}
