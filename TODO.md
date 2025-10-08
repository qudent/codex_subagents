Awesome — here’s a patched, ready-to-implement checklist with all the fixes baked in. It’s ultra-granular and uses [ ] boxes so you (or an engineer) can literally tick things off while building. I’ve folded in the must-fixes (tmux name, quoting, portability, races, etc.) and kept the original flow, but corrected and hardened each step.

⸻

wtx refactor + messaging coverage iteration

[x] 0.0 Capture new requirements in PRD.md (multi-file split, messaging grandchildren coverage, test length guard).
[x] 0.1 Run git pull to sync with main before coding (no upstream remote configured, recorded for review).
[x] 0.2 Lay out updated implementation plan in this TODO checklist (module split, messaging policy expansion, tests) and tick tasks as completed.
[x] 0.2a Split the monolithic wtx script into common/args/state/mux/messaging/close/prune/launch modules and wire a new dispatcher.
[x] 0.2b Extend messaging policy logic to target parent/child/grandchild branches with targeted session delivery.
[x] 0.2c Cover messaging policy across grandchildren with Bats while keeping each test file ≤200 lines.
[x] 0.3 Anchor wtx state storage to the git common dir so nested worktrees share state and close --merge can resolve parents.
[x] 0.4 Replace comm-based branch diffing with portable helpers and split Bats messaging coverage into a separate file to keep suites under 200 lines.

⸻

wtx worktree/mux launcher — Patched Implementation Checklist

Conventions used below:
	•	✔ means a quick rationale; code blocks show the exact incantations to copy.
	•	Steps are idempotent unless marked otherwise.
	•	Everything is Bash (#!/usr/bin/env bash), no zsh-isms.

⸻
Caveats

0.0 [ ] be compatible with the old Mac OS bash version etc.

0) Shell hygiene & mode

[ ] 0.1 Add shebang and strict mode

#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

✔ Prevents subtle quoting/array bugs.

[ ] 0.2 Verify minimum tools (log and skip gracefully)

need() { command -v "$1" >/dev/null 2>&1; }

	•	Required: git
	•	Optional/auto: tmux or screen
	•	Optional features: uv, pnpm

⸻

1) Bootstrap & globals

[ ] 1.1 Parse args: NAME?, -c CMD?, --no-open?, --mux?, --from REF?, --dry-run?, --verbose?, --delete-branches?
[ ] 1.2 Resolve repo & names

REPO_ROOT=$(git rev-parse --show-toplevel) || { echo "Not in a git repo"; exit 1; }
GIT_DIR=$(git rev-parse --git-dir)
REPO_BASENAME=$(basename "$REPO_ROOT")

[ ] 1.3 Defaults

MUX=${MUX:-auto}            # auto|tmux|screen
WTX_GIT_DIR=${WTX_GIT_DIR:-"$GIT_DIR/wtx"}
WTX_UV_ENV=${WTX_UV_ENV:-"$HOME/.wtx/uv-shared"}
WTX_MESSAGING_POLICY=${WTX_MESSAGING_POLICY:-parent,children}
WTX_PROMPT=${WTX_PROMPT:-0} # 1 to mutate PS1 (off by default)

[ ] 1.4 Runtime dirs & perms (log action)

mkdir -p "$WTX_GIT_DIR"/{logs,locks,state}
chmod 700 "$WTX_GIT_DIR" || true


⸻

2) Detect mux backend

[ ] 2.1 Choose backend

if [[ $MUX == auto ]]; then
  if need tmux; then MUX=tmux
  elif need screen; then MUX=screen
  else echo "Need tmux or screen"; exit 2; fi
fi

[ ] 2.2 One-line decision log printed (for diagnostics)

⸻

3) Determine parent & branch name (safe, race-free)

[ ] 3.1 Resolve FROM_REF and parent

FROM_REF=${FROM_REF:-HEAD}
PARENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo detached)
PARENT_SHA=$(git rev-parse "$FROM_REF")
PARENT_SHORT=$(git rev-parse --short "$PARENT_SHA")

[ ] 3.2 If NAME omitted, auto-number with lock
	•	Portable lock (macOS safe):

lockdir="$WTX_GIT_DIR/locks/${PARENT_BRANCH}.lockdir"
while ! mkdir "$lockdir" 2>/dev/null; do sleep 0.05; done
trap 'rmdir "$lockdir" 2>/dev/null || true' EXIT

	•	Scan existing refs with strict regex:

existing=$(git for-each-ref --format='%(refname:short)' \
  "refs/heads/wtx/${PARENT_BRANCH}-*" |
  grep -E "^wtx/${PARENT_BRANCH}-[0-9]+$" |
  sed -E 's/.*-([0-9]+)$/\1/' | sort -n | tail -1 || true)
NN=$(( ${existing:-0} + 1 ))
BRANCH_NAME=${NAME:-"wtx/${PARENT_BRANCH}-${NN}"}

[ ] 3.3 Compute sanitized worktree name

WORKTREE_NAME=$(printf %s "$BRANCH_NAME" | tr '/:' '__')


⸻

4) Ensure branch exists + metadata (robust quoting)

[ ] 4.1 Create branch if missing (with fallback)

if ! git show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
  git branch "$BRANCH_NAME" "$FROM_REF" 2>/dev/null || \
  git branch --no-track "$BRANCH_NAME" "$FROM_REF"
fi

[ ] 4.2 Set description safely

printf -v desc 'wtx: created_by=wtx\nwtx: parent_branch=%s\nwtx: from_ref=%s' \
  "$PARENT_BRANCH" "$FROM_REF"
git config "branch.$BRANCH_NAME.description" "$desc"

[ ] 4.3 Persist tiny state JSON (atomic)

state="$WTX_GIT_DIR/state/$WORKTREE_NAME.json"
tmp=$(mktemp); printf '{"created_by":"wtx","parent_branch":"%s","from_ref":"%s"}\n' \
  "$PARENT_BRANCH" "$FROM_REF" >"$tmp" && mv "$tmp" "$state"


⸻

5) Worktree creation & path (repair zombies)

[ ] 5.1 Paths

WORKTREE_ROOT="$(dirname "$REPO_ROOT")/${REPO_BASENAME}.worktrees"
WT_DIR="$WORKTREE_ROOT/$WORKTREE_NAME"
mkdir -p "$WORKTREE_ROOT"

[ ] 5.2 If dir exists but not registered → repair

if [[ -d "$WT_DIR" ]] && ! git -C "$REPO_ROOT" worktree list --porcelain | grep -q "worktree $WT_DIR"; then
  git -C "$REPO_ROOT" worktree prune || true
fi

[ ] 5.3 Ensure worktree present

if ! git -C "$REPO_ROOT" worktree list --porcelain | grep -q "worktree $WT_DIR"; then
  git -C "$REPO_ROOT" worktree add "$WT_DIR" "$BRANCH_NAME"
fi


⸻

6) Shared uv env (optional, logged)

[ ] 6.1 Create if missing (if uv found)

if need uv; then
  [[ -d "$WTX_UV_ENV" ]] || uv venv "$WTX_UV_ENV"
fi


⸻

7) pnpm install (guarded, stamped)

[ ] 7.1 Skip if no package.json or no pnpm
[ ] 7.2 Use -nt test and atomic stamp

if [[ -f "$WT_DIR/package.json" ]] && need pnpm; then
  PNPM_STAMP="$WT_DIR/.wtx_pnpm_stamp"
  if [[ ! -d "$WT_DIR/node_modules" ]] || [[ "$WT_DIR/pnpm-lock.yaml" -nt "$PNPM_STAMP" ]]; then
    ( cd "$WT_DIR" && pnpm install --frozen-lockfile )
    tmp=$(mktemp) && date +%s >"$tmp" && mv "$tmp" "$PNPM_STAMP"
    PNPM_STATUS=installed
  else
    PNPM_STATUS=skipped
  fi
else
  PNPM_STATUS=none
fi


⸻

8) Session naming (tmux/screen safe)

[ ] 8.1 No colons; sanitize slashes

ses_repo=$(printf %s "$REPO_BASENAME" | tr '/:' '__')
ses_branch=$(printf %s "$BRANCH_NAME" | tr '/:' '__')
SES_NAME="wtx.${ses_repo}.${ses_branch}"

[ ] 8.2 Repo ID (portable hash)

if need sha1sum; then hash_cmd="sha1sum"; else hash_cmd="shasum -a 1"; fi
REPO_ID=$(printf %s "$REPO_ROOT" | eval "$hash_cmd" | cut -c1-8)


⸻

9) Create or attach session

tmux path

[ ] 9.1 Create session if missing

if [[ $MUX == tmux ]]; then
  if ! tmux has-session -t "$SES_NAME" 2>/dev/null; then
    tmux new-session -d -s "$SES_NAME" -c "$WT_DIR"
    tmux set-option  -t "$SES_NAME" @wtx_repo_id "$REPO_ID"
  fi
fi

[ ] 9.2 Prepare tiny init script to avoid brittle send-one-liners

INIT="$WTX_GIT_DIR/state/$WORKTREE_NAME-init.sh"
cat >"$INIT" <<'EOF'
# init injected by wtx
export WTX_UV_ENV="@WTX_UV_ENV@"
if [ -n "$WTX_UV_ENV" ] && [ -d "$WTX_UV_ENV/bin" ]; then
  export PATH="$WTX_UV_ENV/bin:$PATH"
fi
[ "@WTX_PROMPT@" = "1" ] && PS1="[wtx:@BRANCH_NAME@] $PS1"
actions="@ACTIONS@"
printf 'wtx: repo=%s branch=%s parent=%s from=%s actions=[%s]\n' \
  "@REPO_BASENAME@" "@BRANCH_NAME@" "@PARENT_LABEL@" "@FROM_REF@" "$actions"
tmux set-option -t "@SES_NAME@" @wtx_ready 1 2>/dev/null || true
EOF

[ ] 9.3 Template variables safely (quote with %q if needed)

PARENT_LABEL=$([[ "$PARENT_BRANCH" == detached ]] && echo "detached@$PARENT_SHORT" || echo "$PARENT_BRANCH")
ACTIONS="env:$(need uv && echo linked || echo none), pnpm:$PNPM_STATUS, session:$(tmux has-session -t "$SES_NAME" 2>/dev/null && echo reattach || echo created)"
for k in INIT WTX_UV_ENV WTX_PROMPT BRANCH_NAME REPO_BASENAME PARENT_LABEL FROM_REF SES_NAME ACTIONS; do :; done
perl -0777 -pe \
  "s/\@WTX_UV_ENV\@/$(printf %q "$WTX_UV_ENV")/g;
   s/\@WTX_PROMPT\@/$(printf %q "$WTX_PROMPT")/g;
   s/\@BRANCH_NAME\@/$(printf %q "$BRANCH_NAME")/g;
   s/\@REPO_BASENAME\@/$(printf %q "$REPO_BASENAME")/g;
   s/\@PARENT_LABEL\@/$(printf %q "$PARENT_LABEL")/g;
   s/\@FROM_REF\@/$(printf %q "$FROM_REF")/g;
   s/\@SES_NAME\@/$(printf %q "$SES_NAME")/g;
   s/\@ACTIONS\@/$(printf %q "$ACTIONS")/g;" \
  -i "$INIT"

[ ] 9.4 Source init in pane, set ready flag

tmux send-keys -t "$SES_NAME" ". $INIT" C-m

[ ] 9.5 Attach or switch client

if [[ -z "${NO_OPEN:-}" ]]; then
  if [[ -n "${TMUX:-}" ]]; then
    tmux switch-client -t "$SES_NAME"
  else
    tmux attach -t "$SES_NAME"
  fi
else
  echo "Attach with: tmux attach -t '$SES_NAME'"
fi

screen path (only if MUX=screen)

[ ] 9.6 Create session if missing

if [[ $MUX == screen ]]; then
  if ! screen -ls | grep -q "\.${SES_NAME}[[:space:]]"; then
    screen -dmS "$SES_NAME" sh -c "cd '$WT_DIR'; exec \$SHELL"
  fi
  screen -S "$SES_NAME" -p 0 -X stuff "export WTX_UV_ENV='$(printf %q "$WTX_UV_ENV")'$(printf '\r')"
  screen -S "$SES_NAME" -p 0 -X stuff "export PATH='$(printf %q "$WTX_UV_ENV")/bin:\$PATH'$(printf '\r')"
  screen -S "$SES_NAME" -p 0 -X stuff "$(printf "printf 'wtx: repo=%%s branch=%%s parent=%%s from=%%s actions=[%%s]\\n' %q %q %q %q %q" \
    "$REPO_BASENAME" "$BRANCH_NAME" "$PARENT_LABEL" "$FROM_REF" "$ACTIONS")$(printf '\r')"
  [[ -z "${NO_OPEN:-}" ]] && screen -r "$SES_NAME" || echo "Attach with: screen -r '$SES_NAME'"
fi


⸻

10) Readiness & raw keystrokes (-c)

[ ] 10.1 tmux ready probe (safe alias)

ready=$(tmux show-options -v -t "$SES_NAME" @wtx_ready 2>/dev/null || echo 0)

[ ] 10.2 Send raw keystrokes

if [[ -n "${CMD:-}" ]]; then
  if [[ $MUX == tmux ]]; then tmux send-keys -t "$SES_NAME" "$CMD" C-m
  else screen -S "$SES_NAME" -p 0 -X stuff "$CMD$(printf '\r')"
  fi
fi

✔ No parsing/eval; exactly what the user typed.

⸻

11) Messaging (parent/children) — optional

[ ] 11.1 tmux sessions discovery by @wtx_repo_id
[ ] 11.2 Compose comment line (no side effects)
[ ] 11.3 Send via send-keys to targets (guard with policy flag)

⸻

12) Prune (wtx prune)

[ ] 12.1 Enumerate mux sessions; kill those whose worktree dirs vanished (dry-run first)
[ ] 12.2 Compare $WORKTREE_ROOT/* vs git worktree list → remove orphan dirs (dry-run)
[ ] 12.3 Optionally delete merged refs/heads/wtx/* only with --delete-branches
[ ] 12.4 Print a columnar dry-run report before doing anything destructive

⸻

13) Logging

[ ] 13.1 One-line run log in date file (atomic)

logf="$WTX_GIT_DIR/logs/$(date +%F).log"
tmp=$(mktemp)
printf '%s %s actions=[%s]\n' "$(date -Iseconds)" "$BRANCH_NAME" "$ACTIONS" >>"$tmp"
cat "$tmp" >>"$logf" && rm -f "$tmp"


⸻

14) Concurrency cleanup

[ ] 14.1 trap removes lockdir on all exits
[ ] 14.2 All stamps/state via mktemp && mv (already done)

⸻

15) Tests (bats/bash)

[ ] 15.1 Temp repo → init, commit, run tool → asserts: branch/worktree created
[ ] 15.2 Idempotency: second run doesn’t recreate
[ ] 15.3 -c 'echo OK' captured by tmux capture-pane / screen -X hardcopy
[ ] 15.4 pnpm path: create package.json + lock → first install runs, second skipped
[ ] 15.5 Ready flag set/read
[ ] 15.6 Prune dry-run vs real
[ ] 15.7 Both tmux and screen modes (if available)
[ ] 15.8 Attach while already inside tmux → switch-client works

⸻

16) Docs

[ ] 16.1 Flags & env vars (WTX_GIT_DIR, WTX_UV_ENV, WTX_MESSAGING_POLICY, MUX, WTX_PROMPT)
[ ] 16.2 Examples (wtx -c 'pytest -q') + attach instructions
[ ] 16.3 Security note: raw keystrokes; no auth/protocol by design
[ ] 16.4 Troubleshooting: zombie worktrees; PNPM missing; macOS flock fallback

⸻

17) Nits & polish

[ ] 17.1 git branch --no-track fallback already included
[ ] 17.2 Log that chmod 700 ran (surprising on shared boxes)
[ ] 17.3 Actions list assembled as env:…, pnpm:…, session:…
[ ] 17.4 Banner shows parent=<name|detached@abcd123> and from=<REF>
[ ] 17.5 GUI “focus” is reduced to printing attach command unless user requests AppleScript/XDG openers

⸻

Example final banner (single line)

wtx: repo=my-repo branch=wtx/main-003 parent=main from=HEAD actions=[env:linked, pnpm:skipped, session:created]


⸻

If you want, I can now convert this into a single Bash file that implements everything above (≈250–300 LOC) with the exact quoting and tmux/screen branches — just say the word and I’ll drop the script.