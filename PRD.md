Perfect — you’re asking for the complete context + vision of wtx rewritten as a structured, fine-grained checklist where every single step or assumption is something that can be ticked off or verified during implementation or review.
Below is exactly that: a practical, readable “execution spec” for wtx, including both the intended behavior and the implementation checklist you can literally check box by box.

⸻

✅ wtx Vision & Intended Usage (context checklist)

0. Purpose & concept

[ ] Goal: one command (wtx) to spin up, resume, and send live commands into self-contained branch workspaces (“living branches”).
[ ] Behavior: it creates a Git branch, worktree, and development shell (tmux or screen session) automatically.
[ ] Philosophy: each branch = its own living environment, always reproducible, instantly accessible, but sharing a single Python/JS environment for efficiency.
[ ] Primary audience: solo developers or small teams who iterate rapidly on multiple short-lived feature branches.
[ ] Outcome: typing

wtx feature-x -c "pytest -q"

creates or reuses everything and runs the command inside the right worktree/shell.

⸻

1. Invocation interface

[ ] Command form:
wtx [branch-name] [-c 'string'] [--no-open] [--mux tmux|screen] [--from REF] [--close|--close-merge|--close-force],
[ ] If branch-name omitted → autogenerate as wtx/<parent>-NN.
[ ] -c sends raw keystrokes to the session and presses Enter.
[ ] --mux selects backend (default: auto → prefer tmux).
[ ] --no-open suppresses GUI terminal focus.
[ ] --from selects parent commit (defaults to current HEAD).

[ ] --close will spin down that branch+worktree+tmux in the end/after this command is finished, aborting if there are uncommitted changes
[ ] --close-merge will commit, merge, then close
[ ] --close-force will spin down even with uncommitted changes

[ ] So to spin down a particular branch without command: wtx [branch-name] --close
[ ] to spin down the branch we are in now: wtx $(git rev-parse --abbrev-ref HEAD) --close

wtx close [--force|--merge] [branch-name] spins down branch-name, deletes worktree, branch, tmux, branch-name, with [--merge] committing+merging everything into current branch, with [--force] closing even if there are uncommitted changes, without [branch-name] when run from a particular worktree/branch tmux it will finish this branch itself
⸻

2. Branch creation & metadata

[ ] Verify target branch exists; if not, create it from --from or current HEAD.
[ ] Save minimal metadata in branch description:

wtx: created_by=wtx
wtx: parent_branch=<name-or-none>

[ ] Do not store timestamps or SHA hashes.
[ ] Ensure branch description write is idempotent (re-runs don’t duplicate).
[ ] Keep this metadata human-readable (git config branch.<name>.description).

⸻

3. Worktree setup

[ ] Worktree path: ../<repo>.worktrees/<branch-name> relative to repo root.
[ ] If not present → git worktree add <path> <branch>.
[ ] If present → verify the path and branch match (idempotency).
[ ] Never touch untracked worktrees not created by wtx.

⸻

4. Environment policy

[ ] Python: use one shared uv environment (not per-worktree).
    [ ] Env path: $WTX_UV_ENV (default ~/.wtx/uv-shared).
    [ ] Create on first use: uv venv "$WTX_UV_ENV".
    [ ] Prepend "$WTX_UV_ENV/bin" to PATH for each session.
[ ] JavaScript: use pnpm.
    [ ] Run pnpm install --frozen-lockfile only if node_modules missing or lockfile changed.
    [ ] Rely on pnpm’s global store; never share node_modules directories.
[ ] [ ] All env operations must be idempotent (re-running wtx never damages an existing env).

⸻

5. Multiplexer session

[ ] Choose backend:
    [ ] tmux preferred; fallback to screen if tmux not installed.
[ ] Session name format: wtx:<repo-name>:<branch-name> (unique per repo).
[ ] Create session rooted at the worktree:
    tmux → tmux new-session -d -s "$SES_NAME" -c "$WT_DIR"
    screen → screen -dmS "$SES_NAME" bash -c "cd '$WT_DIR'; exec bash".
[ ] Print a one-line banner inside the session:

wtx: repo=<repo> branch=<branch> parent=<parent> actions=[env, pnpm, ready]

[ ] Expose a tmux variable @wtx_ready=1 (or mark ready in screen) after shell init.
[ ] Re-use existing session if present.
[ ] Keep same naming to permit fast attach.

⸻

6. Input & live command sending

[ ] -c flag triggers raw keystroke send:
    tmux → tmux send-keys -t "$SES_NAME" "$CMD" C-m
    screen → screen -S "$SES_NAME" -p 0 -X stuff "$CMD$(printf '\r')"
[ ] No parsing, no eval — send literally as if typed by user.
[ ] If tmux session variable @wtx_ready absent → send anyway (raw).
[ ] Confirm hot path completes in ≤25 ms on modern hardware.

⸻

7. GUI behavior

[ ] If --no-open not set:
    [ ] Try to focus/open a GUI terminal attached to the session
        macOS → AppleScript tell app "Terminal" to do script "tmux attach -t $SES"
        Linux → $TERMINAL -e "tmux attach -t $SES".
[ ] If focusing fails → print the attach command for manual use.

⸻

8. Messaging policy

[ ] Environment variable WTX_MESSAGING_POLICY controls cross-session notices (parent,children default).
[ ] On new commit or branch event → build message:

# [wtx] on <branch>: commit <sha> "<msg>" — merge: git merge <sha>

[ ] Send this line as raw keystrokes to targeted sessions (tmux/screen).
[ ] Ensure it’s commented (#) so it’s safe if pasted in shell.
[ ] No complex protocol — just informative notifications.

⸻

9. Prune command

[ ] Command: wtx prune [--dry-run].
[ ] Enumerate all worktrees and sessions.
[ ] For each:
    [ ] If worktree directory missing → kill session.
    [ ] If branch is wtx/* and fully merged → delete (unless --dry-run).
    [ ] Else leave intact.
[ ] Summarize deletions and skipped items.
[ ] Never touch non-wtx branches or worktrees.

⸻

10. State & logs

[ ] All runtime data stored under $WTX_GIT_DIR/wtx/ inside .git:

$WTX_GIT_DIR/wtx/
  logs/
  locks/
  state/

[ ] Never write to working tree; never commit these files.
[ ] Always create dirs 700 permissions.
[ ] Log each command run with timestamp → $WTX_GIT_DIR/wtx/logs/YYYY-MM-DD.log.

⸻

11. Banner verification

[ ] When user attaches, first line printed should always show repo, branch, parent, and summary of actions (linked, created, skipped, etc.).
[ ] Banner content comes from variables captured at runtime.
[ ] Verify in both tmux and screen modes.

⸻

12. Performance & idempotency

[ ] Cold start: includes worktree add + pnpm install → seconds (depends on project).
[ ] Warm start: worktree and env exist → ≤400 ms.
[ ] Hot path (-c send): ≤25 ms typical (tmux).
[ ] Re-running wtx multiple times should never duplicate branches or sessions.
[ ] Output should clearly say whether each resource was created, reused, or skipped.

⸻

13. Testing & validation

[ ] Create BATS or shell test suite.
[ ] Tests:
    [ ] Auto-branch naming works sequentially.
    [ ] Worktree reuse idempotent.
    [ ] Shared uv env detected/created once.
    [ ] pnpm install runs only on first spawn.
    [ ] -c command sends correctly (verify via tmux capture).
    [ ] prune --dry-run lists expected items.
[ ] Run tests for both tmux and screen backends.

⸻

14. Documentation & ergonomics

[ ] Provide README section with example workflow:

# start new branch
wtx feature-x
# run quick test
wtx feature-x -c 'pytest -q'
# open again later
wtx feature-x

[ ] Explain environment variables (WTX_GIT_DIR, WTX_UV_ENV, WTX_MESSAGING_POLICY).
[ ] Clarify that raw keystrokes are unfiltered (behave like manual typing).
[ ] Include troubleshooting: “session exists”, “worktree already exists”, etc.

⸻

15. Future/optional features

[ ] Add --debug flag for verbose logging.
[ ] Add wtx attach alias for convenience.
[ ] Add tab-completion script.
[ ] Optionally integrate simple progress messages (spinner or [ok]).
[ ] Optionally support wtx prune --delete-branches.

⸻

16. Key design invariants

[ ] Everything runs within one repo; no cross-repo effects.
[ ] No background daemons.
[ ] All state ephemeral in .git/wtx/.
[ ] Shared uv env only; per-worktree envs discouraged.
[ ] tmux/screen abstraction minimal—no feature loss if one missing.
[ ] Raw keystroke injection only; no FIFO protocol or auth overhead.

⸻

✅ Result:
After every checklist item is implemented and ticked, the user experience is:

# create a new living branch environment
wtx
# attach automatically
# see banner: wtx: repo=foo branch=wtx/main-003 parent=main actions=[env, pnpm:skipped]
# run code/tests
wtx -c "pytest"

All worktrees are in ../repo.worktrees/…, all state lives in .git/wtx/, and attaching to any branch instantly restores its environment.