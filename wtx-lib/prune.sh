# prune helpers

wtx_prune_command() {
  actions=0
  prefix="wtx_${SANITIZED_REPO}_"
  if need tmux; then
    tmux_lines=$(tmux list-sessions -F '#{session_name} #{@wtx_repo_id}' 2>/dev/null || true)
    OLDIFS="$IFS"; IFS=$'\n'
    for line in $tmux_lines; do
      sess=$(printf '%s' "$line" | awk '{print $1}')
      repo_id=$(printf '%s' "$line" | awk '{print $2}')
      case "$sess" in
        ${prefix}*)
          [ "$repo_id" = "$REPO_ID" ] || continue
          sanitized=${sess#$prefix}
          branch=$(wtx_branch_from_state_file "$WTX_GIT_DIR_ABS/state/${sanitized}.json")
          if [ -z "$branch" ]; then
            echo "kill-session $sess (unknown branch)"; actions=1
            [ "$PRUNE_DRY_RUN" -eq 1 ] || tmux kill-session -t "$sess" >/dev/null 2>&1 || true
            continue
          fi
          wt_dir=$(wtx_worktree_dir_for_branch "$branch")
          if [ ! -d "$wt_dir" ]; then
            echo "kill-session $sess (orphaned)"; actions=1
            [ "$PRUNE_DRY_RUN" -eq 1 ] || tmux kill-session -t "$sess" >/dev/null 2>&1 || true
          fi
          ;;
      esac
    done
    IFS="$OLDIFS"
  fi
  if need screen; then
    screen_lines=$(screen -ls 2>/dev/null | awk '/\t/ {print $1}' || true)
    OLDIFS="$IFS"; IFS=$'\n'
    for entry in $screen_lines; do
      session=${entry#*.}
      case "$session" in
        ${prefix}*)
          branch=$(wtx_branch_from_state_file "$WTX_GIT_DIR_ABS/state/${session#$prefix}.json")
          if [ -z "$branch" ]; then
            echo "kill-session $session (unknown branch)"; actions=1
            [ "$PRUNE_DRY_RUN" -eq 1 ] || screen -S "$session" -X quit >/dev/null 2>&1 || true
            continue
          fi
          wt_dir=$(wtx_worktree_dir_for_branch "$branch")
          if [ ! -d "$wt_dir" ]; then
            echo "kill-session $session (orphaned)"; actions=1
            [ "$PRUNE_DRY_RUN" -eq 1 ] || screen -S "$session" -X quit >/dev/null 2>&1 || true
          fi
          ;;
      esac
    done
    IFS="$OLDIFS"
  fi
  worktree_root=$(wtx_worktree_root)
  if [ -d "$worktree_root" ]; then
    git -C "$REPO_ROOT" worktree list --porcelain \
      | awk '/^worktree /{sub(/^worktree /, ""); print}' >"$WTX_GIT_DIR_ABS/.tracked"
    while IFS= read -r -d '' path; do
      [ -e "$path" ] || continue
      if ! grep -Fxq "$path" "$WTX_GIT_DIR_ABS/.tracked"; then
        echo "rm-worktree $path"; actions=1
        if [ "$PRUNE_DRY_RUN" -eq 0 ]; then
          rm -rf "$path"
          rm -f "$WTX_GIT_DIR_ABS/state/$(basename "$path").json"
        fi
      fi
    done < <(find "$worktree_root" -mindepth 1 -maxdepth 1 -print0 2>/dev/null)
    rm -f "$WTX_GIT_DIR_ABS/.tracked"
  fi
  if [ "$PRUNE_DELETE_BRANCHES" -eq 1 ]; then
    merged=$(git -C "$REPO_ROOT" branch --list 'wtx/*' --merged 2>/dev/null || true)
    OLDIFS="$IFS"; IFS=$'\n'
    for branch in $merged; do
      branch=$(printf '%s' "$branch" | tr -d ' *')
      [ -n "$branch" ] || continue
      wt_dir=$(wtx_worktree_dir_for_branch "$branch")
      [ -d "$wt_dir" ] && continue
      echo "delete-branch $branch"; actions=1
      [ "$PRUNE_DRY_RUN" -eq 1 ] && continue
      git -C "$REPO_ROOT" branch -d "$branch" >/dev/null 2>&1 || git -C "$REPO_ROOT" branch -D "$branch" >/dev/null 2>&1
    done
    IFS="$OLDIFS"
  fi
  if [ "$actions" -eq 0 ]; then
    echo "[wtx] prune: nothing to do"
  else
    if [ "$PRUNE_DRY_RUN" -eq 0 ]; then
      git -C "$REPO_ROOT" worktree prune >/dev/null 2>&1 || true
      echo "[wtx] prune complete"
    else
      echo "[wtx] prune dry-run complete"
    fi
  fi
}
