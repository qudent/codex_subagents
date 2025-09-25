# --- helpers reused ---
_wt_repo_root(){ git rev-parse --show-toplevel 2>/dev/null; }
_wt_slug(){ printf "%s" "$1" | tr '[:space:]/:' '-' | tr -cd '[:alnum:]-_.'; }
_wt_uid(){ printf "%s-%s" "$(date +%y%m%d-%H%M)" "$(hexdump -n2 -e '2/1 "%02x"' /dev/urandom 2>/dev/null || echo 0000)"; }
_wt_repo_tag(){
  local root name hash
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
_wt_js_install(){
  if command -v npm >/dev/null 2>&1 && [ -f package-lock.json ]; then npm ci || true; return; fi
  if command -v pnpm >/dev/null 2>&1 && [ -f pnpm-lock.yaml ]; then pnpm install --frozen-lockfile || true; return; fi
  if command -v yarn >/dev/null 2>&1 && [ -f yarn.lock ]; then yarn install --frozen-lockfile || true; return; fi
}

# === spinup_worker (unchanged behavior, now anchored to per-repo base dir) ===
spinup_worker(){
  local short="${1:-worker}"; short="$(_wt_slug "$short")"
  local base="${2:-main}"

  local root tag uid base_dir wt_dir wt_path session branch src_env
  root="$(_wt_repo_root)" || { echo "❌ Not in a Git repo." >&2; return 1; }
  command -v tmux >/dev/null 2>&1 || { echo "❌ tmux not found." >&2; return 1; }
  command -v osascript >/dev/null 2>&1 || { echo "❌ osascript (macOS) not found." >&2; return 1; }

  tag="$(_wt_repo_tag)" || { echo "❌ Failed to build repo tag" >&2; return 1; }
  uid="$(_wt_uid)"
  base_dir="${WT_BASE:-$HOME/.worktrees}/${tag}"
  mkdir -p "$base_dir"

  wt_dir="${tag}-wt-${short}-${uid}"
  wt_path="${base_dir}/${wt_dir}"
  session="$wt_dir"                 # tmux session == worktree dir (unique, scoped)
  branch="worker/${short}-${uid}"
  src_env="${root}/.env"

  echo "👉 creating branch ${branch} from ${base}"
  if git rev-parse --verify -q "refs/remotes/origin/${base}" >/dev/null; then
    git branch "$branch" "origin/${base}" || { echo "❌ Failed to create branch" >&2; return 1; }
  else
    git branch "$branch" "$base" || { echo "❌ Failed to create branch" >&2; return 1; }
  fi

  echo "👉 adding worktree at ${wt_path}"
  git worktree add "$wt_path" "$branch" || { echo "❌ git worktree add failed" >&2; return 1; }

  [ -f "$src_env" ] && [ ! -f "${wt_path}/.env" ] && cp "$src_env" "${wt_path}/.env" || true
  ( cd "$wt_path" && _wt_js_install ) || true

  local usershell="${SHELL:-/bin/bash}"
  tmux new-session -d -s "$session" -c "$wt_path" "$usershell" -l || { echo "❌ tmux new-session failed" >&2; return 1; }

  read -r -d '' setup_cmd <<'EOS' || true
[ -f .venv/bin/activate ] && . .venv/bin/activate || true
if [ -f .env ]; then set -a; . ./.env; set +a; fi
if [ -f package-lock.json ] || [ -f pnpm-lock.yaml ] || [ -f yarn.lock ]; then
  if command -v npm >/dev/null 2>&1 && [ -f package-lock.json ]; then npm ci || true; fi
  if command -v pnpm >/dev/null 2>&1 && [ -f pnpm-lock.yaml ]; then pnpm install --frozen-lockfile || true; fi
  if command -v yarn >/dev/null 2>&1 && [ -f yarn.lock ]; then yarn install --frozen-lockfile || true; fi
fi
clear
echo "✅ Ready in $(pwd)"
EOS
  tmux send-keys -t "$session:0.0" "$setup_cmd" C-m

  osascript >/dev/null <<EOF
tell application "Terminal"
  activate
  do script "tmux attach -t ${session} || tmux new -s ${session}"
end tell
EOF

  echo "✅ worker up
   repo:     $tag
   session:  $session
   worktree: $wt_path
   branch:   $branch"
}

# === clean_worktrees (scoped, anchored, deletes branches, optional prune) ===
clean_worktrees(){
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
  base_dir="${WT_BASE:-$HOME/.worktrees}/${tag}"

  command -v tmux >/dev/null 2>&1 || { echo "❌ tmux not found"; return 1; }

  echo "👉 scanning for repo: $tag"
  local sessions; sessions="$(tmux list-sessions -F "#{session_name}" 2>/dev/null || true)"

  # 1) remove stale worktrees under this repo’s base_dir
  if [ -d "$base_dir" ]; then
    find "$base_dir" -maxdepth 1 -type d -name "${tag}-wt-*" | while IFS= read -r wt; do
      local name; name="$(basename "$wt")"
      if printf "%s\n" "$sessions" | grep -qx "$name"; then
        continue  # session alive
      fi

      # Discover branch from git metadata
      local branch
      branch="$(git worktree list --porcelain | awk -v p="$wt" '
        $1=="worktree" && $2==p { inwt=1; next }
        inwt && $1=="branch" { sub("refs/heads/","",$2); print $2; exit }')"

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
  printf "%s\n" "$sessions" | grep -E "^${tag}-wt-" || true | while IFS= read -r s; do
    local wt="${base_dir}/${s}"
    if [ ! -d "$wt" ]; then
      echo "✂️  killing orphan tmux session: $s"
      [ $DRY -eq 1 ] && echo "   (dry-run) tmux kill-session -t \"$s\"" || tmux kill-session -t "$s" || true
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