**wtx TODO (reconciled and simplified)**

Vision
- One terminal window per agent (tmux session). No in-place session switching.
- Two-command experience for most users: create a new attempt, and see attempts.
- Syntax reminds of `git worktree (add|list)`
- Messaging of new commits: `wtx message` includes the latest commit, and a sentence like "latest commit: <message> `git merge <commit-hash> in your window to merge the latest changes`")" in each message to notify parents/children of updates.
- `finish_worktree` or quitting tmux automatically sends message that something is ready to merge etc.
- Cleanup is automatic or one-shot; no dangling worktrees/branches/sessions.

Immediate Changes
- change `wtx ls` to `wtx list`
- `wtx list` should show the mapping users need.
  - Show: `branch`, `parent`, `path`, `session`, `state(running|missing)`.
  - Source from `.git/wtx.meta/<branch>.env` and `tmux has-session`.
  - path shows the intended worktree dir, and we annotate if it’s absent: path=/…/
  s003-main-login (missing)

  So a typical line would read:

  - branch, parent, path=/…/s003-main-login, session=wtx:s003-main-login,
  state=running

  And stale cases are obvious:

  - path=… (missing), session=wtx:… , state=missing → prune will delete the
  metadata/branch residue.
  - path=… (present), session=wtx:… , state=missing → prune will remove session
  metadata and branch if needed (per your rule: if any piece is stale, delete
  the rest).

- `wtx rm <branch>` must delete everything by default.
  - Delete tmux session, worktree folder, and the git branch.

- `wtx prune` reconciles stale state.
  - For each meta entry: if any of worktree/branch/session is missing, delete the rest and remove metadata.
  - Safe by construction: acts only on entries under this repo’s metadata.

- Cross‑platform window open.
  - Keep macOS `osascript` default; support `WTX_OPEN_CMD` for Linux/BSD (e.g., `alacritty -e`, `kitty -e`, `gnome-terminal --`).
  - Always open a new window attached to the session (no attach-in-place command).
  - If `WTX_OPEN_CMD` is set, use it verbatim to run `bash -lc 'tmux attach -t <session>'`.
  - Headless/SSH: if no GUI terminal is found (or no display), print the exact attach command and return success without blocking.

- Messaging unification (advanced).
  - Replace `notify_parents`/`notify_children` with `wtx message [--policy parents|children|all] [--keys] <msg>`.
  - Support `WTX_MESSAGING_POLICY` default. Keep as advanced docs, not in Quickstart.

README Simplification
- Lead with the “two commands” flow:
  - `wtx create -d "idea"` opens a new window for the attempt.
  - Run again for parallel attempts. Use your OS to switch between windows.
- Show only: `wtx ls`, `wtx open <branch>`, `wtx rm <branch>`, `wtx prune`.
- Move `-p/--parent` to Advanced with guidance: “checkout desired parent, then run `wtx create`.”
- Move tmux primer, env bootstrap details, and messaging to Advanced.

- Env var naming
  - Goal: All exported env vars should be `WTX_…` (e.g., `WTX_PARENT_BRANCH`, `WTX_BRANCH`, `WTX_SESSION`, `WTX_WORKTREE`).
  - Current: Mixed — meta and tmux export `BRANCH`, `PARENT_BRANCH`, `SESSION`, `WORKTREE` without `WTX_` prefix.
  - Plan:
    - Add `WTX_…` exports alongside current names for backward compatibility.
    - Mark unprefixed names as deprecated in README (keep them for now).
    - Update tests once the transition is complete.

- Reduce options / fewer footguns
  - Hide `-p` from Quickstart; keep as Advanced only.
  - No “session switching” verbs; always open a new OS window attached.
  - Keep `env-setup` as an internal boot step; don’t document as a user action.

- Branch management “inside”
  - `wtx rm` deletes the git branch by default (and tmux/worktree). Provide `--keep-branch` to retain.
  - `wtx prune` removes any half‑state across tmux/worktree/branch.

- Session prefix naming
  - Request: Session prefix should default to the repo directory name instead of `wtx`; collisions are acceptable.
  - Plan: Change default of `WTX_SESSION_PREFIX` to `$(basename $(git rev-parse --show-toplevel))` and keep the env var override.

- Finish/Merge UX
  - Idea: `wtx finish` to guide merge (e.g., back to parent/main) and cleanup.
  - Plan: Start minimal: print exact merge commands and offer `--cleanup` to run `rm` on success. Keep out of Quickstart.

- Commit/cleanup messaging
  - Idea: Emit a commit message template or tmux note on cleanup/finish with how to merge.
  - Plan: Add optional `WTX_FINISH_NOTE=1` to append to a repo‑local log or display via tmux when `finish` runs.

- venv activation report
  - Observation: “venv entering doesn’t seem to work.” Current behavior: we only activate if `.venv/bin/activate` exists in the worktree. We symlink `.venv` from repo root if present; we do not create a venv.
  - Plan: Document clearly; optionally add `WTX_VENV_AUTO_CREATE=python3 -m venv .venv` hook for users who want auto‑creation (off by default to avoid surprises).

Nice‑to‑Have (NOT NOW)
- automatically open a tiny dashboard (`watch -n1 wtx ls` or a portable loop) in a new window+tmux if not yet visible.
- `wtx doctor` to validate git/tmux availability and OS opener config.
- `wtx rename <old> <new>` to move branch/worktree/meta coherently (defer until core is stable).

Notes for Tests
- Keep `test_wtx_flow.sh` comprehensive. Add a fast smoke test that does: create → ls → open → rm (no messaging) for contributor sanity.
