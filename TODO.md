# wtx TODO

## Vision
- One tmux session per agent; no inline session switching.
- Keep functionality minimal and agent-focused.
- `wtx create` adds worktree in `<repo>.worktrees/<name>`, links `.venv`, activates the environment, runs installs, and names the tmux session `repo/branch`.
- `wtx message` is the primary communication channel; hashtag-prefixed updates share merge commands.

## Phase 1 – Core Agent Loop
- [x] Implement `wtx create <name>` with worktree setup, tmux session, and post-commit hook for messaging.
- [x] Implement `wtx message` to notify parent and child sessions automatically.
- [x] Implement `wtx list` as a wrapper around `git worktree list`.
- [x] Implement `wtx prune` to remove stale worktrees.
- [x] Write a minimal `README.md` outlining the agent workflow (`wtx create`, commit triggers `wtx message`, exit tmux, `wtx prune`) and documenting `wtx list`.
- [x] in the help text when running wtx, include a short phrase explaining what the commands do
- [x] wtx prune should also delete the branches, not just the worktrees (--force for deleting unmerged/uncommitted changes). but only the branches starting with the prefix.
- [ ] fix the current fact that no env vars are read/venv isn't entered
- [ ] run a refactor/tightening/making concise of wtx

- [x] fix weird behavior that there shouldn't be recursive worktrees, by always constructing worktree path based on root repository .git directory -- currently recursive wtx worktree doesn't work.
- [x] make wtx list actually show whether things are [TMUX ACTIVE] or [TMUX INACTIVE], and show message how to enter the tmuxes.

## Phase 2 – Refinement
- [ ] Implement `wtx finish` to merge, announce completion, and optionally prune.
- [ ] Standardize environment variables (`WTX_*`) and tmux naming conventions.
- [ ] Update install script/README with tmux quality-of-life settings (`set -g mouse on`, `set -g history-limit 100000`, `tmux source-file ~/.tmux.conf`).
