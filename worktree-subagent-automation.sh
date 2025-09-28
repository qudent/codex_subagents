# --- helpers reused ---
_wt_repo_root() { git rev-parse --show-toplevel 2>/dev/null; }
_wt_slug() { printf "%s" "$1" | tr '[:space:]/:' '-' | tr -cd '[:alnum:]-_.'; }
_wt_uid() { printf "%s-%s" "$(date +%y%m%d-%H%M)" "$(hexdump -n2 -e '2/1 "%02x"' /dev/urandom 2>/dev/null || echo 0000)"; }
_wt_repo_tag() {
  root="$(_wt_repo_root)" || return 1
  name="$(basename "$root" | tr -cd '[:alnum:]-_.')"
  if command -v shasum >/dev/null 2>&1; then
    hash="$(printf "%s" "$(cd "$root" && pwd -P)" | shasum -a 1 | cut -c1-6)"
  elif command -v md5 >/dev/null 2>&1; then
    hash="$(printf "%s" "$(cd "$root" && pwd -P)" | md5 | cut -c1-6)"
  else
    hash="local"
  fi
  printf "%s-%s" "$name" "$hash"
}
_wt_js_install() {
  if command -v npm >/dev/null 2>&1 && [ -f package-lock.json ]; then npm ci || true; return; fi
  if command -v pnpm >/dev/null 2>&1 && [ -f pnpm-lock.yaml ]; then pnpm install --frozen-lockfile || true; return; fi
  if command -v yarn >/dev/null 2>&1 && [ -f yarn.lock ]; then yarn install --frozen-lockfile || true; return; fi
}

# === spinup_worker ===
spinup_worker() {
  short="$1"; if [ -z "$short" ]; then short="worker"; fi; short="$(_wt_slug "$short")"
  base="$2"; if [ -z "$base" ]; then base="main"; fi

  root="$(_wt_repo_root)" || { echo "❌ Not in a Git repo." >&2; return 1; }
  command -v tmux >/dev/null 2>&1 || { echo "❌ tmux not found." >&2; return 1; }

  os_name="$(uname -s 2>/dev/null || echo unknown)"
  if command -v osascript >/dev/null 2>&1 && [ "$os_name" = "Darwin" ]; then
    opener="osascript"
  elif [ "$os_name" = "Linux" ] && command -v xterm >/dev/null 2>&1; then
    opener="xterm"
  else
    echo "❌ no supported terminal launcher found (need osascript on macOS or xterm on Linux)." >&2
    return 1
  fi

  tag="$(_wt_repo_tag)" || { echo "❌ Failed to build repo tag" >&2; return 1; }
  uid="$(_wt_uid)"
  base_dir="${WT_BASE:-$HOME/.worktrees}/$tag"
  mkdir -p "$base_dir"

  # concise worktree/session name
  wt_dir="$tag-$short-$uid"
  wt_path="$base_dir/$wt_dir"
  session="$wt_dir"
  branch="worker/$short-$uid"
  src_env="$root/.env"

  echo "👉 creating branch $branch from $base"
  if git rev-parse --verify -q "refs/remotes/origin/$base" >/dev/null; then
    git branch "$branch" "origin/$base" || { echo "❌ Failed to create branch" >&2; return 1; }
  else
    git branch "$branch" "$base" || { echo "❌ Failed to create branch" >&2; return 1; }
  fi

  echo "👉 adding worktree at $wt_path"
  git worktree add "$wt_path" "$branch" || { echo "❌ git worktree add failed" >&2; return 1; }

  if [ -f "$src_env" ] && [ ! -f "$wt_path/.env" ]; then cp "$src_env" "$wt_path/.env"; fi
  (cd "$wt_path" && _wt_js_install) || true

  usershell="$SHELL"; if [ -z "$usershell" ]; then usershell="/bin/sh"; fi
  tmux new-session -d -s "$session" -c "$wt_path" "$usershell" -l || { echo "❌ tmux new-session failed" >&2; return 1; }

  setup_cmd="[ -f .venv/bin/activate ] && . .venv/bin/activate || true; if [ -f .env ]; then set -a; . ./.env; set +a; fi; if [ -f package-lock.json ] || [ -f pnpm-lock.yaml ] || [ -f yarn.lock ]; then if command -v npm >/dev/null 2>&1 && [ -f package-lock.json ]; then npm ci || true; fi; if command -v pnpm >/dev/null 2>&1 && [ -f pnpm-lock.yaml ]; then pnpm install --frozen-lockfile || true; fi; if command -v yarn >/dev/null 2>&1 && [ -f yarn.lock ]; then yarn install --frozen-lockfile || true; fi; fi; clear; echo '✅ Ready in $(pwd)'"
  tmux send-keys -t "$session:0.0" "$setup_cmd" C-m

  if [ "$opener" = "osascript" ]; then
    osascript >/dev/null <<EOF
      tell application "Terminal"
        activate
        do script "tmux attach -t ${session} || tmux new -s ${session}"
      end tell
EOF
  else
    "${opener}" -T "$session" -e "$usershell" -lc "tmux attach -t ${session} || tmux new -s ${session}" &
  fi

  echo "✅ worker up\n   repo:     $tag\n   session:  $session\n   worktree: $wt_path\n   branch:   $branch"
}

_wt_session_to_path() {
  # map a session name to its worktree path (repo-scoped base dir + session)
  tag="$(_wt_repo_tag)" || return 1
  base_dir="${WT_BASE:-$HOME/.worktrees}/$tag"
  printf "%s/%s" "$base_dir" "$1"
}

_wt_infer_wtpath() {
  # priority: explicit arg (session or path) -> current tmux session -> cwd worktree
  arg="$1"
  wt=""
  if [ -n "$arg" ]; then
    if [ -d "$arg" ]; then
      wt="$arg"
    else
      # treat as session name
      wt="$(_wt_session_to_path "$arg")"
      [ -d "$wt" ] || wt=""
    fi
  fi
  if [ -z "$wt" ] && [ -n "$(_wt_guess_session)" ]; then
    wt="$(_wt_session_to_path "$(_wt_guess_session)")"
    [ -d "$wt" ] || wt=""
  fi
  if [ -z "$wt" ]; then
    here="$(pwd -P)"
    wt="$(git worktree list --porcelain | awk -v here="$here" '
      $1=="worktree" { p=$2; if (index(here,p)==1) { print p; exit } }
    ')"
  fi
  printf "%s" "$wt"
}

# --- clean_worktrees (scoped, anchored, deletes branches, optional prune) ===
clean_worktrees() {
  local FORCE=0 DRY=0 PRUNE=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --force) FORCE=1 ;;
      --dry-run) DRY=1 ;;
      --prune-branches) PRUNE=1 ;;
      *) echo "usage: clean_worktrees [--dry-run] [--force] [--prune-branches]"; return 1;;
    esac
    shift
  done

  local root tag base_dir
  root="$(_wt_repo_root)" || { echo "❌ Not in a Git repo." >&2; return 1; }
  tag="$(_wt_repo_tag)"   || { echo "❌ Failed to build repo tag" >&2; return 1; }
  base_dir="${WT_BASE:-$HOME/.worktrees}/$tag"

  command -v tmux >/dev/null 2>&1 || { echo "❌ tmux not found"; return 1; }

  echo "👉 scanning for repo: $tag"
  local sessions; sessions="$(tmux list-sessions -F "#{session_name}" 2>/dev/null || true)"

  # 1) remove stale worktrees under this repo’s base_dir
  if [ -d "$base_dir" ]; then
    find "$base_dir" -maxdepth 1 -type d -name "${tag}-*" | while IFS= read -r wt; do
      local name; name="$(basename "$wt")"
      if printf "%s\n" "$sessions" | grep -qx "$name"; then
        continue  # session alive
      fi

      # Discover branch from git metadata
      local branch
      branch="$(git worktree list --porcelain | awk -v p="$wt" '
        $1=="worktree" && $2==p { inwt=1; next }
        inwt && $1=="branch" { sub("refs/heads/","",$2); print $2; exit }')"

      if [ -z "$branch" ]; then
        echo "🗑 removing stale worktree: $wt (not registered)"
        if [ $DRY -eq 1 ]; then
          echo "   (dry-run) rm -rf \"$wt\""
        else
          rm -rf "$wt" || { echo "   ⛔ failed to remove $wt"; continue; }
        fi
        continue
      fi

      local dirty=0
      if [ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ]; then dirty=1; fi
      if [ $dirty -eq 1 ] && [ $FORCE -ne 1 ]; then
        echo "⚠️  dirty worktree (skip without --force): $wt"
        continue
      fi

      echo "🗑 removing stale worktree: $wt"
      if [ $DRY -eq 1 ]; then
        echo "   (dry-run) git worktree remove ${FORCE:+--force} \"$wt\""
        [ -n "$branch" ] && echo "   (dry-run) git branch -D \"$branch\""
      else
        git worktree remove ${FORCE:+--force} "$wt" || { echo "   ⛔ failed to remove $wt"; continue; }
        if [ -n "$branch" ] && git show-ref --verify --quiet "refs/heads/${branch}"; then
          git branch -D "$branch" || true
        fi
      fi
    done
  fi

  # 2) kill orphan tmux sessions for this repo tag
  printf "%s\n" "$sessions" | grep -E "^${tag}-" | while IFS= read -r s; do
    local wt="${base_dir}/${s}"
    if [ ! -d "$wt" ]; then
      echo "✂️  killing orphan tmux session: $s"
      if [ $DRY -eq 1 ]; then
        echo "   (dry-run) tmux kill-session -t \"$s\""
      else
        tmux kill-session -t "$s" || true
      fi
    fi
  done

  # 3) optional: prune stray worker/* branches
  if [ $PRUNE -eq 1 ]; then
    echo "🪓 pruning stray worker/* branches not in any worktree…"
    git for-each-ref --format='%(refname:short) %(worktreepath)' refs/heads/worker/ \
    | while read -r br path; do
        if [ -z "$path" ]; then
          echo "   deleting $br"
          [ $DRY -eq 1 ] && echo "   (dry-run) git branch -D \"$br\"" || git branch -D "$br" || true
        fi
      done
  fi

  echo "✅ cleanup complete for repo: $tag"
}

# --- small helpers ----------------------------------------------------------

_wt_branch_for_worktree() {
  # prints the short branch name for a given worktree path
  local wt="$1"
  git worktree list --porcelain | awk -v p="$wt" '
    $1=="worktree" && $2==p { inwt=1; next }
    inwt && $1=="branch" { sub("refs/heads/","",$2); print $2; exit }'
}

_wt_path_for_branch() {
  # prints the worktree path that has <branch> checked out (empty if none)
  local br="$1"
  git worktree list --porcelain | awk -v br="$br" '
    $1=="worktree" { cur=$2; next }
    $1=="branch" {
      b=$2
      sub("refs/heads/","",b)
      if (b==br) { print cur; exit }
    }
  '
}

_wt_guess_session() {
  # if inside tmux, print current session name; else empty
  if [ -n "${TMUX:-}" ] && command -v tmux >/dev/null 2>&1; then
    tmux display-message -p '#S'
  fi
}

# --- merge one worker into main (without finishing) -------------------------

merge_worker() {
  # usage: merge_worker [<session-or-worktree-path>] [--target main] [--no-ff|--ff-only]
  local target="main" ff="--ff-only" arg=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --target) shift; target="${1:-main}" ;;
      --no-ff)  ff="--no-ff" ;;
      --ff-only) ff="--ff-only" ;;
      *) arg="$1" ;;
    esac; shift
  done

  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "❌ not in a git repo"; return 1; }

  local wt; wt="$(_wt_infer_wtpath "$arg")"
  [ -n "$wt" ] && [ -d "$wt" ] || { echo "❌ cannot resolve worker worktree"; return 1; }

  local feature; feature="$(_wt_branch_for_worktree "$wt")"
  [ -n "$feature" ] || { echo "❌ could not determine feature branch"; return 1; }

  # safety: require clean index in the worker
  if [ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ]; then
    echo "❌ worktree has uncommitted changes: $wt"; echo "   commit/stash or run finish_worker --force"; return 1
  fi

  echo "👉 rebasing '$feature' onto latest $target"
  git fetch --all --quiet || true
  git -C "$wt" pull --ff-only || true  # update remotes in this worktree env
  if git rev-parse --verify -q "origin/$target" >/dev/null; then
    git -C "$wt" rebase "origin/$target" || { echo "❌ rebase failed"; return 1; }
  else
    git -C "$wt" rebase "$target" || { echo "❌ rebase failed"; return 1; }
  fi

  # find where target is checked out
  local main_wt; main_wt="$(_wt_path_for_branch "$target")"
  if [ -n "$main_wt" ]; then
    echo "👉 merging '$feature' into '$target' in $main_wt ($ff)"
    git -C "$main_wt" fetch --quiet origin || true
    git -C "$main_wt" merge $ff "$feature" || { echo "❌ merge failed"; return 1; }
    git -C "$main_wt" push -u origin "$target" || true
  else
    echo "👉 '$target' not checked out; merging here"
    git -C "$wt" checkout "$target" || { echo "❌ cannot checkout $target in worker"; return 1; }
    git -C "$wt" merge $ff "$feature" || { echo "❌ merge failed"; return 1; }
    git -C "$wt" push -u origin "$target" || true
    # restore feature checkout for continued work
    git -C "$wt" checkout "$feature" || true
  fi

  echo "✅ merged '$feature' -> '$target'"
}

# --- finish a worker: merge + remove worktree + delete branch + kill session -

finish_worker() {
  # usage: finish_worker [<session-or-worktree-path>] [--target main] [--no-ff|--ff-only] [--force]
  local target="main" ff="--ff-only" force=0 arg=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --target)   shift; target="${1:-main}" ;;
      --no-ff)    ff="--no-ff" ;;
      --ff-only)  ff="--ff-only" ;;
      --force)    force=1 ;;
      *) arg="$1" ;;
    esac; shift
  done

  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "❌ not in a git repo"; return 1; }

  local wt; wt="$(_wt_infer_wtpath "$arg")"
  [ -n "$wt" ] && [ -d "$wt" ] || { echo "❌ cannot resolve worker worktree"; return 1; }

  local feature; feature="$(_wt_branch_for_worktree "$wt")"
  [ -n "$feature" ] || { echo "❌ could not determine feature branch"; return 1; }

  dirty_state="$(git -C "$wt" status --porcelain 2>/dev/null)"
  if [ -n "$dirty_state" ]; then
    if [ $force -eq 0 ]; then
      echo "❌ worktree has uncommitted changes: $wt"
      echo "   commit/stash or re-run with --force to discard them"
      return 1
    fi

    echo "⚠️  discarding uncommitted changes in $wt"
    git -C "$wt" reset --hard HEAD >/dev/null 2>&1 || {
      echo "❌ failed to reset worktree"; return 1;
    }
    git -C "$wt" clean -fd >/dev/null 2>&1 || {
      echo "❌ failed to clean worktree"; return 1;
    }
  fi

  # merge first (reuses the logic above)
  merge_worker "$wt" --target "$target" $ff || return 1

  # after successful merge, remove the worktree and delete the branch
  echo "👉 removing worktree: $wt"
  if [ $force -eq 1 ]; then
    git worktree remove --force "$wt" || { echo "❌ failed to remove worktree"; return 1; }
  else
    git worktree remove "$wt" || { echo "❌ failed to remove worktree (use --force?)"; return 1; }
  fi

  if git show-ref --verify --quiet "refs/heads/${feature}"; then
    echo "👉 deleting branch: $feature"
    git branch -D "$feature" || true
  fi

  # kill the associated tmux session if it exists (same name as worktree folder)
  if command -v tmux >/dev/null 2>&1; then
    local sess="$(basename "$wt")"
    if tmux list-sessions -F '#S' 2>/dev/null | grep -qx "$sess"; then
      echo "👉 killing tmux session: $sess"
      tmux kill-session -t "$sess" || true
    fi
  fi

  echo "✅ finished worker '$feature' into '$target'"
}
