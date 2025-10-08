# repo + branch/worktree state helpers

wtx_init_repo_context() {
  REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "Not inside a git repo"; exit 1; }
  GIT_DIR=$(git rev-parse --git-dir)
  GIT_COMMON_DIR=$(git rev-parse --git-common-dir)
  REPO_BASENAME=$(basename "$REPO_ROOT")
  SANITIZED_REPO=$(sanitize_component "$REPO_BASENAME")

  case "$GIT_COMMON_DIR" in
    /*) GIT_COMMON_DIR_ABS="$GIT_COMMON_DIR" ;;
    *) GIT_COMMON_DIR_ABS="$REPO_ROOT/$GIT_COMMON_DIR" ;;
  esac

  if [ -n "${WTX_GIT_DIR+x}" ]; then
    case "$WTX_GIT_DIR" in
      /*) WTX_GIT_DIR_ABS="$WTX_GIT_DIR" ;;
      *) WTX_GIT_DIR_ABS="$REPO_ROOT/$WTX_GIT_DIR" ;;
    esac
  else
    WTX_GIT_DIR_ABS="$GIT_COMMON_DIR_ABS/wtx"
    WTX_GIT_DIR="$GIT_COMMON_DIR/wtx"
  fi

  mkdir -p "$WTX_GIT_DIR_ABS"/logs "$WTX_GIT_DIR_ABS"/locks "$WTX_GIT_DIR_ABS"/state
  chmod 700 "$WTX_GIT_DIR_ABS" || true

  if need sha1sum; then
    REPO_ID=$(printf %s "$GIT_COMMON_DIR_ABS" | sha1sum | cut -c1-8)
  else
    REPO_ID=$(printf %s "$GIT_COMMON_DIR_ABS" | shasum -a 1 | awk '{print $1}' | cut -c1-8)
  fi
}

wtx_state_file_for_branch() {
  printf '%s/state/%s.json' "$WTX_GIT_DIR_ABS" "$(sanitize_component "$1")"
}

wtx_worktree_dir_for_branch() {
  printf '%s/%s.worktrees/%s' "$(dirname "$REPO_ROOT")" "$REPO_BASENAME" "$(sanitize_component "$1")"
}

wtx_existing_worktree_path() {
  git -C "$REPO_ROOT" worktree list --porcelain \
    | awk -v target="$1" '
        /^worktree / { path=$0; sub(/^worktree /, "", path) }
        /^branch / {
          ref=$0; sub(/^branch /, "", ref); sub(/^refs\/heads\//, "", ref)
          if (ref == target) { print path; exit }
        }
      '
}

wtx_session_name_for_branch() {
  branch="$1"
  state_file=$(wtx_state_file_for_branch "$branch")
  session_repo=$(wtx_read_state_field "$state_file" session_repo)
  if [ -z "$session_repo" ]; then
    session_repo="$SANITIZED_REPO"
  fi
  printf 'wtx_%s_%s' "$session_repo" "$(sanitize_component "$branch")"
}

wtx_read_state_field() {
  [ -f "$1" ] || { echo ""; return; }
  sed -n "s/.*\"$2\":\"\([^\"]*\)\".*/\1/p" "$1" | head -n 1
}

wtx_branch_from_state_file() {
  file="$1"
  branch=$(wtx_read_state_field "$file" branch_name)
  if [ -n "$branch" ]; then
    printf '%s' "$branch"
    return
  fi
  base=$(basename "$file")
  sanitized=${base%.json}
  OLDIFS="$IFS"
  IFS=$'\n'
  refs=$(git -C "$REPO_ROOT" for-each-ref --format='%(refname:short)' 'refs/heads/*' 2>/dev/null || true)
  for ref in $refs; do
    if [ "$(sanitize_component "$ref")" = "$sanitized" ]; then
      printf '%s' "$ref"
      IFS="$OLDIFS"
      return
    fi
  done
  IFS="$OLDIFS"
}

wtx_parent_for_branch() {
  branch="$1"
  state_file=$(wtx_state_file_for_branch "$branch")
  parent=$(wtx_read_state_field "$state_file" parent_branch)
  if [ -n "$parent" ]; then
    printf '%s' "$parent"
    return
  fi
  desc=$(git config --get "branch.$branch.description" 2>/dev/null || true)
  printf '%s\n' "$desc" | sed -n 's/^wtx: parent_branch=//p' | head -n 1
}

wtx_acquire_parent_lock() {
  lock_key=$(sanitize_component "$1")
  WTX_LOCKDIR="$WTX_GIT_DIR_ABS/locks/${lock_key}.lockdir"
  while ! mkdir "$WTX_LOCKDIR" 2>/dev/null; do sleep 0.05; done
  trap wtx_release_parent_lock EXIT
}

wtx_release_parent_lock() {
  if [ -n "${WTX_LOCKDIR:-}" ]; then
    rmdir "$WTX_LOCKDIR" 2>/dev/null || true
    WTX_LOCKDIR=""
  fi
}

wtx_prepare_branch_selection() {
  PARENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo detached)
  PARENT_SHA=$(git rev-parse "$FROM_REF")
  PARENT_SHORT=$(git rev-parse --short "$PARENT_SHA")
  wtx_acquire_parent_lock "$PARENT_BRANCH"

  if [ -z "$NAME" ]; then
    existing=$(git for-each-ref --format='%(refname:short)' "refs/heads/wtx/${PARENT_BRANCH}-*" 2>/dev/null | grep -E "^wtx/${PARENT_BRANCH}-[0-9]+$" || true)
    last=$(printf '%s\n' "$existing" | sed -n 's/.*-\([0-9][0-9]*\)$/\1/p' | sort -n | tail -n 1)
    NN=$(( ${last:-0} + 1 ))
    BRANCH_NAME="wtx/${PARENT_BRANCH}-${NN}"
  else
    BRANCH_NAME="$NAME"
  fi

  WORKTREE_NAME=$(sanitize_component "$BRANCH_NAME")
  STATE_FILE=$(wtx_state_file_for_branch "$BRANCH_NAME")
}

wtx_ensure_branch_materialized() {
  if ! git show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
    git branch "$BRANCH_NAME" "$FROM_REF" 2>/dev/null || git branch --no-track "$BRANCH_NAME" "$FROM_REF"
  fi

  desc="wtx: created_by=wtx\nwtx: parent_branch=${PARENT_BRANCH}\nwtx: from_ref=${FROM_REF}"
  git config "branch.$BRANCH_NAME.description" "$desc" || true

  tmp=$(mktemp "$WTX_GIT_DIR_ABS/tmp.XXXXXX")
  printf '{"created_by":"wtx","branch_name":"%s","parent_branch":"%s","from_ref":"%s","session_repo":"%s"}\n' "$BRANCH_NAME" "$PARENT_BRANCH" "$FROM_REF" "$SANITIZED_REPO" >"$tmp"
  mv "$tmp" "$STATE_FILE"
}

wtx_worktree_root() {
  printf '%s/%s.worktrees' "$(dirname "$REPO_ROOT")" "$REPO_BASENAME"
}

wtx_ensure_worktree() {
  existing_path=$(wtx_existing_worktree_path "$BRANCH_NAME")
  if [ -n "$existing_path" ]; then
    WT_DIR="$existing_path"
    return
  fi
  WORKTREE_ROOT=$(wtx_worktree_root)
  WT_DIR="$WORKTREE_ROOT/$WORKTREE_NAME"
  mkdir -p "$WORKTREE_ROOT"
  if [ -d "$WT_DIR" ] && ! git -C "$REPO_ROOT" worktree list --porcelain | awk '/^worktree /{sub(/^worktree /, "", $0); print}' | grep -Fxq "$WT_DIR"; then
    git -C "$REPO_ROOT" worktree prune >/dev/null 2>&1 || true
  fi
  if ! git -C "$REPO_ROOT" worktree list --porcelain | awk '/^worktree /{sub(/^worktree /, "", $0); print}' | grep -Fxq "$WT_DIR"; then
    git -C "$REPO_ROOT" worktree add "$WT_DIR" "$BRANCH_NAME"
  fi
}
