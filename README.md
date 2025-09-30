NOT updated readme.md yet. IGNORE THIS. source of truth is currently wtx.sh

# Parallelize your vibecoding by worktrees + tmux!
## What?
This script has helper functions that
- make vibecoding agents working in parallel on the same repo (on different features, or letting different agents have a go at the same problem) seamless by spawning in one go
- a new branch whose description includes which branch it was "called from"
- a new git worktree (checked out copy of that branch) for coding agents
- a new tmux session in that branch
- setting up python/node environment (sourcing/linking .env), npm ci, source .venv/bin/activate when applicable (submit a PR for other dev setups!)
- showing a terminal (mac os/linux) with that tmux session
- providing quick commands for merging from "child branch", and keeping other agents in other tmux sessions up to date by sending keystrokes to them with latest commits (`notify_parent` and `notify_children` helpers)
- opinionated: everything relevant should be an empty commit message (e.g. "ran tests"), every commit informs parent and invites to merge


, copying and sourcing tmux sessions, and terminals showing them.
## Why?
You would really like to parallelize your vibecoding agents!
- you may wait quite a long time for the agent to finish one job and you get bored
- want to experiment with different models/approaches for one task
- you may not know in advance what or how much firepower to direct at something (gpt-5 high is better but much pricier and slower than gpt-oss via groq/openrouter)
- the cost of fixing stuff is often higher than the cost of starting anew

The git solution to working in parallel are _worktrees_, which allow you to have different branches checked out in 
# Getting started
Clone the repo: `git clone <repo_url>`
# How it works

# Subagent Worktree Automation


Utilities for spinning up Git worktrees backed by dedicated tmux sessions, then merging and cleaning them up without manual bookkeeping.

## Features
- Direct `spinup_worker` command that creates a scoped branch, adds a worktree under `${WT_BASE:-$HOME/.worktrees}`, copies `.env`, installs JS deps (npm/pnpm/yarn), and launches a tmux session ready to work via `osascript` on macOS or `xterm` on Linux.
- `merge_worker` keeps the feature worktree rebased on a target branch (default `main`), then merges that feature branch back (fast-forward by default, configurable with `--no-ff` or `--ff-only`) and pushes when possible.
- `finish_worker` wraps merge + cleanup, removing the worktree, deleting the worker branch, and killing the paired tmux session (use `--force` to ignore a dirty tree).
- `clean_worktrees` sweeps repo-specific worktrees, trims orphaned tmux sessions, and optionally prunes `worker/*` branches. Supports `--dry-run` to print the actions that _would_ run and `--force` to clean dirty trees.
- Helper script `test_wt_workers.sh` demonstrates repo bootstrap, tmux interactions, merge flow, dry-run cleanup, and branch pruning edge cases.

## Usage
Source `worktree-subagent-automation.sh` inside a Git repository and call the helpers from a worker worktree (or pass a session/worktree explicitly):

```sh
. ./worktree-subagent-automation.sh
spinup_worker feature-a              # creates worker/feature-a-<uid>
merge_worker                         # run _inside_ the worker so the branch/worktree can be inferred
finish_worker --target main --ff-only
clean_worktrees --dry-run             # list cleanup steps without executing them
```

`merge_worker` figures out which worker branch to merge by inspecting the worktree you're in (or a session/worktree argument you pass). `--dry-run` on `clean_worktrees` only logs the would-be removals so you can check before running the real cleanup.

Requires Git, tmux, and (optionally) a JS package manager for dependency install hooks, and works from either Bash or Zsh shells.
