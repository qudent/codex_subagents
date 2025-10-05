# wtx TODO

## Vision
- One tmux session per agent; no inline session switching.
- Keep functionality minimal and agent-focused.
- `wtx open` opens a tmux associated with every branch.
- `wtx open [branch] [-c 'string']` sends 'string' to the branch. the following state:
   - branch `branch` exists (if not given as argument, it creates a new branch based on the current branches name and the parent branch.)
   - `branch` is open in some worktree (if not exists or worktree prunable, prunes and recreates. it makes sure to link .env, .venv, and run pnpm install in the worktree)
   - there is a tmux whose name correponds to the repo+branch name (if that doesn't exist, it starts it, also exports env vars from .env and runs source .venv/bin/activate if applicable)
   - unless `WTX_GUI_OPEN` is set to 0, open gui window
   - type the command `string` into that terminal with tmux send-keys if this was given by -c.
   
   for an open branch, or for a new branch based on current commit and name in running counter if [branch] is not given:
   - does a `git worktree list`
   - if [branch] doesn't exist, create a branch and writes parent branch (where it was branched off from) into description/parents. naming scheme as in current code.
   - creates a worktree for that branch in `<repo>.worktrees/<name>` if that doesn't yet exist (or has been deleted/is prunable)
   - links `.venv`, activates the environment, runs installs, and names the tmux session `repo/branch`.
- `wtx message` is the primary communication channel; hashtag-prefixed updates share merge commands.

## Phase 1 – Core Agent Loop
- [x] Implement `wtx create <name>` with worktree setup, tmux session, and post-commit hook for messaging.
- [x] Implement `wtx message` to notify parent and child sessions automatically.
- [x] Implement `wtx list` as a wrapper around `git worktree list`.
- [x] Implement `wtx prune` to remove stale worktrees.
- [x] Write a minimal `README.md` outlining the agent workflow (`wtx create`, commit triggers `wtx message`, exit tmux, `wtx prune`) and documenting `wtx list`.
- [x] in the help text when running wtx, include a short phrase explaining what the commands do
- [x] wtx prune should also delete the branches, not just the worktrees (--force for deleting unmerged/uncommitted changes). but only the branches starting with the prefix.
- [ ] fix the current fact that no env vars are read/venv isn't entered/pnpm install is not attempted
- [ ] when a terminal opens, this should be run and briefly acknowledged, branch and parent name and fact that committing will message according to messaging policy should be acknowledged as well.

- [x] fix weird behavior that there shouldn't be recursive worktrees, by always constructing worktree path based on root repository .git directory -- currently recursive wtx worktree doesn't work.
- [x] make wtx list actually show whether things are [TMUX ACTIVE] or [TMUX INACTIVE], and show message how to enter the tmuxes.
[ ] delete wtx list functionality + behavior + documentation as it will be replaced by wtx open
[ ] delete wtx cleanup functionality + behavior + documentation, as wtx prune
will be the way to do it


- [ ] run a refactor/tightening/making concise of wtx code
- [ ] double check that README etx doesn't contain anything of previous README.md
## Phase 2 – Refinement
- [ ] Implement `wtx finish` to merge, announce completion, and optionally prune.
- [ ] Standardize environment variables (`WTX_*`) and tmux naming conventions.
- [ ] Update install script/README with tmux quality-of-life settings (`set -g mouse on`, `set -g history-limit 100000`, `tmux source-file ~/.tmux.conf`).
