# ~/.wt_workers_scoped.sh
# Scoped workers per-repo: tmux sessions & worktrees are prefixed with a repo tag

_wt_info(){ printf "👉 %s\n" "$*"; }
_wt_err(){ printf "❌ %s\n" "$*" >&2; }

_wt_repo_root(){ git rev-parse --show-toplevel 2>/dev/null; }
_wt_slug(){ printf "%s" "$1" | tr '[:space:]/:' '-' | tr -cd '[:alnum:]-_.'; }
_wt_uid(){ printf "%s-%s" "$(date +%y%m%d-%H%M)" "$(hexdump -n2 -e '2/1 "%02x"' /dev/urandom 2>/dev/null || echo 0000)"; }

# Build a stable, repo-unique tag: <repo-name>-<short-hash-of-abs-path>
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

# Create worker: tmux session name == worktree dir name; both prefixed with repo tag
# usage: spinup_worker ["short-name"] [base_branch=main]
spinup_worker(){
  local short="${1:-worker}"; short="$(_wt_slug "$short")"
  local base="${2:-main}"

  local root; root="$(_wt_repo_root)" || { _wt_err "Not in a Git repo."; return 1; }
  command -v tmux >/dev/null 2>&1 || { _wt_err "tmux not found"; return 1; }
  command -v osascript >/dev/null 2>&1 || { _wt_err "osascript not found (macOS only)"; return 1; }

  local tag uid base_dir wt_dir wt_path session branch src_env
  tag="$(_wt_repo_tag)" || { _wt_err "Failed to build repo tag"; return 1; }
  uid="$(_wt_uid)"
  base_dir="${WT_BASE:-$HOME/.worktrees}/${tag}"
  mkdir -p "$base_dir"
  wt_dir="${tag}-wt-${short}-${uid}"
  wt_path="${base_dir}/${wt_dir}"
  session="$wt_dir"                            # session == worktree folder
  branch="worker/${short}-${uid}"
  src_env="${root}/.env"

  _wt_info "🌿 creating branch ${branch} from ${base}"
  if git rev-parse --verify -q "refs/remotes/origin/${base}" >/dev/null; then
    git branch "$branch" "origin/${base}" || { _wt_err "Failed to create branch"; return 1; }
  else
    git branch "$branch" "$base" || { _wt_err "Failed to create branch"; return 1; }
  fi

  _wt_info "🧱 adding worktree at ${wt_path}"
  git worktree add "$wt_path" "$branch" || { _wt_err "git worktree add failed"; return 1; }

  [ -f "$src_env" ] && [ ! -f "${wt_path}/.env" ] && cp "$src_env" "${wt_path}/.env" || true
  ( cd "$wt_path" && _wt_js_install ) || true

  local usershell="${SHELL:-/bin/bash}"
  tmux new-session -d -s "$session" -c "$wt_path" "$usershell" -l || { _wt_err "tmux new-session failed"; return 1; }

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

  printf "%s\n" "$branch" > "${wt_path}/.worker.branch" || true
  _wt_info "✅ worker up
   repo:     $tag
   session:  $session
   worktree: $wt_path
   branch:   $branch"
}

# Scoped cleaner: only touches sessions/worktrees for THIS repo tag
# usage: clean_worktrees [--dry-run] [--force]
clean_worktrees(){
  local FORCE=0 DRY=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --force)  FORCE=1 ;;
      --dry-run) DRY=1 ;;
      *) echo "usage: clean_worktrees [--dry-run] [--force]"; return 1;;
    esac
    shift
  done

  local root; root="$(_wt_repo_root)" || { _wt_err "Not in a Git repo."; return 1; }
  local tag; tag="$(_wt_repo_tag)" || { _wt_err "Failed to build repo tag"; return 1; }
  command -v tmux >/dev/null 2>&1 || { _wt_err "tmux not found"; return 1; }

  _wt_info "🧹 scanning for repo: $tag"
  local sessions; sessions="$(tmux list-sessions -F "#{session_name}" 2>/dev/null || true)"

  # 1) remove stale worktrees for this tag (basename starts with "${tag}-wt-")
  git worktree list --porcelain \
  | awk '$1=="worktree"{print $2}' \
  | while IFS= read -r wt; do
      [ -d "$wt" ] || continue
      local name; name="$(basename "$wt")"
      case "$name" in
        ${tag}-wt-*) ;;     # our repo's workers
        *) continue ;;
      esac
      # Skip if tmux session with the same name exists
      if printf "%s\n" "$sessions" | grep -qx "$name"; then
        continue
      fi

      # Discover branch
      local branch
      branch="$(git worktree list --porcelain | awk -v p="$wt" '
        $1=="worktree" && $2==p { inwt=1; next }
        inwt && $1=="branch" { sub("refs/heads/","",$2); print $2; exit }')"

      # Dirty check
      local dirty=0
      if [ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ]; then dirty=1; fi
      if [ $dirty -eq 1 ] && [ $FORCE -ne 1 ]; then
        echo "⚠️  dirty worktree (skip without --force): $wt"
        continue
      fi

      echo "🗑 removing stale worktree: $wt"
      if [ $DRY -eq 1 ]; then
        echo "   (dry-run) git worktree remove ${FORCE:+--force} \"$wt\""
      else
        git worktree remove ${FORCE:+--force} "$wt" || { echo "   ⛔ failed to remove $wt"; continue; }
        if [ -n "$branch" ] && git show-ref --verify --quiet "refs/heads/${branch}"; then
          git branch -D "$branch" || true
        fi
      fi
    done

  # 2) kill orphan tmux sessions for this tag (sessions named "${tag}-wt-*")
  printf "%s\n" "$sessions" | grep -E "^${tag}-wt-" || true | while IFS= read -r s; do
    # Does a worktree with this basename exist?
    local found=0
    git worktree list --porcelain | awk '$1=="worktree"{print $2}' | while IFS= read -r w; do
      [ "$(basename "$w")" = "$s" ] && found=1
    done
    if [ ${found:-0} -eq 0 ]; then
      echo "✂️  killing orphan tmux session: $s"
      [ $DRY -eq 1 ] && echo "   (dry-run) tmux kill-session -t \"$s\"" || tmux kill-session -t "$s" || true
    fi
  done

  _wt_info "✅ cleanup complete for repo: $tag"
}