# close/merge helpers

auto_commit_if_needed() {
  branch="$1"
  dir="$2"
  [ -d "$dir" ] || { echo ""; return; }
  git -C "$dir" add -A >/dev/null 2>&1 || true
  if [ -n "$(git -C "$dir" status --porcelain 2>/dev/null)" ]; then
    git -C "$dir" commit -m "wtx: auto-commit before merge" >/dev/null
    git -C "$dir" rev-parse HEAD
  else
    echo ""
  fi
}

wtx_close_branch() {
  branch="$1"; mode="$2"
  [ -n "$branch" ] || die "no branch resolved for close"
  state_file=$(wtx_state_file_for_branch "$branch")
  wt_dir=$(wtx_worktree_dir_for_branch "$branch")

  if [ "$mode" != "force" ] && [ "$mode" != "merge" ] && [ -d "$wt_dir" ]; then
    if [ -n "$(git -C "$wt_dir" status --porcelain 2>/dev/null)" ]; then
      die "worktree has uncommitted changes; use --force"
    fi
  fi

  parent_branch=$(wtx_parent_for_branch "$branch")

  if [ "$mode" = "merge" ]; then
    [ -n "$parent_branch" ] && [ "$parent_branch" != "detached" ] || die "cannot merge: parent unknown"
    commit_sha=$(auto_commit_if_needed "$branch" "$wt_dir")
    if [ -n "$commit_sha" ]; then
      short=$(printf '%s' "$commit_sha" | cut -c1-7)
      subject=$(git -C "$wt_dir" log -1 --pretty=%s "$commit_sha")
      wtx_send_repo_message "$branch" "# [wtx] on $branch: commit $short \"$subject\""
    fi
    parent_wt=$(wtx_existing_worktree_path "$parent_branch")
    merge_root="$REPO_ROOT"
    restore=""
    if [ -n "$parent_wt" ]; then
      merge_root="$parent_wt"
      if [ -n "$(git -C "$merge_root" status --porcelain 2>/dev/null)" ]; then
        die "cannot merge: parent worktree dirty"
      fi
      if ! git -C "$merge_root" merge --ff-only "$branch" >/dev/null 2>&1; then
        die "merge failed (needs manual resolution)"
      fi
    else
      current_branch=$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo detached)
      current_head=$(git -C "$REPO_ROOT" rev-parse HEAD)
      if [ "$current_branch" != "$parent_branch" ]; then
        [ -z "$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null)" ] || die "cannot merge: main worktree dirty"
        git -C "$REPO_ROOT" checkout --quiet "$parent_branch" >/dev/null 2>&1 || die "failed to checkout $parent_branch"
        if [ "$current_branch" = "detached" ] || [ "$current_branch" = "HEAD" ]; then
          restore="--detach $current_head"
        else
          restore="$current_branch"
        fi
      fi
      if ! git -C "$REPO_ROOT" merge --ff-only "$branch" >/dev/null 2>&1; then
        if [ "$restore" = "--detach $current_head" ]; then
          git -C "$REPO_ROOT" checkout --quiet --detach "$current_head" >/dev/null 2>&1 || true
        elif [ -n "$restore" ]; then
          git -C "$REPO_ROOT" checkout --quiet "$restore" >/dev/null 2>&1 || true
        fi
        die "merge failed (needs manual resolution)"
      fi
      if [ "$restore" = "--detach $current_head" ]; then
        git -C "$REPO_ROOT" checkout --quiet --detach "$current_head" >/dev/null 2>&1 || true
      elif [ -n "$restore" ]; then
        git -C "$REPO_ROOT" checkout --quiet "$restore" >/dev/null 2>&1 || true
      fi
    fi
    merge_sha=$(git -C "$merge_root" rev-parse "$parent_branch")
    merge_short=$(printf '%s' "$merge_sha" | cut -c1-7)
    wtx_send_repo_message "$branch" "# [wtx] merge $branch -> $parent_branch at $merge_short"
  fi

  wtx_kill_sessions_for_branch "$branch"

  if [ -d "$wt_dir" ]; then
    if [ "$mode" = "force" ]; then
      git -C "$REPO_ROOT" worktree remove --force "$wt_dir" >/dev/null 2>&1 || rm -rf "$wt_dir"
    else
      git -C "$REPO_ROOT" worktree remove "$wt_dir" >/dev/null 2>&1 || die "failed to remove worktree"
    fi
  fi

  if git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/$branch"; then
    case "$mode" in
      merge) git -C "$REPO_ROOT" branch -d "$branch" >/dev/null 2>&1 || git -C "$REPO_ROOT" branch -D "$branch" >/dev/null 2>&1 || true ;;
      force) git -C "$REPO_ROOT" branch -D "$branch" >/dev/null 2>&1 || true ;;
      *) git -C "$REPO_ROOT" branch -D "$branch" >/dev/null 2>&1 || true ;;
    esac
  fi

  rm -f "$state_file"
  wtx_send_repo_message "$branch" "# [wtx] closed $branch (mode=$mode)"
  echo "[wtx] closed $branch"
  return 0
}
