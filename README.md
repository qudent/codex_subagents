# wtx

`wtx` is a lightweight helper for Git worktrees and tmux sessions tuned for autonomous coding agents. Each branch gets its own workspace and terminal, and every commit automatically pings the relevant peers with merge instructions.

## Agent Workflow
1. Create a workspace with `./wtx create [name]` (optional [name]). It spawns a Git worktree, links shared environment assets, and opens a dedicated tmux session.
2. Make changes and commit as usual inside the tmux pane. The post-commit hook runs `wtx message`, which tells the parent/child branches exactly how to merge the new work.
3. Check active agents with `./wtx list`. The output shows the parent branch, tmux status, and the command to attach to each session.
4. When the worktree is no longer needed, run `./wtx prune` to remove any inactive directories and tmux sessions.

## Commands
- `wtx create [NAME] [-p|--parent BRANCH] [-c|--command "..."]` – Prepare a new agent workspace, optionally specifying the parent branch or a bootstrap command to run inside tmux.
- `wtx message` – Notify the parent and child agents about the most recent commit, including the merge command.
- `wtx list` – Show all worktrees with parent relationships, tmux status, and the attach command.
- `wtx prune` – Clean up pruned Git worktrees and kill stale tmux sessions.

## Environment
- `WTX_CONTAINER_DEFAULT` – Override the directory that stores worktrees (defaults to `<repo>.worktrees` alongside the main repo).
- `WTX_MESSAGING_POLICY` – Control who receives `wtx message` broadcasts (`parent`, `children`, or `all`).
