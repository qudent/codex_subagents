# wtx TODO

## Vision
- "imbue branches with life and send command": one command
- `wtx [branch-name] [-c 'string'] [--no-open]` makes it so that there is
- a branch called branch-name -- in case the branch does not exist, it gets created, including info encoded in description that it was wtx-created and "spawned" from the current branch (or detached commit), if it already exists, creation doesn't happen
- if branch-name not given, choose wtx branch with scheme "wtx-<parent-branch-running-counter"
- a worktree with that branch -- if not exist, it gets set up AND we link .env, .venv, run pnpm install in that worktree
- a tmux with a shell cd in that worktree - if no exist we open in that branch for standard dev setups, make sure that shell prints out branch and parent branch in beginning, print that we did/didn't link .env .venv ran pnpm install sources (with export!) .env, source .venv/bin/activate if relevant
- if -c is passed, we pass 'string' via sendkeys to that tmux as command/update
- and a GUI terminal (via osascript/linux terminal) showing that tmux, if it already exists we put it into focus, if focusing fails we reopen term (as apparently mgmt file is stale). --no-show overrides opening/focusing.
- we output the correct tmux attach command for relevant session
- when setting up wtx branch we have post checkout messaging which according to WTX_MESSAGING_POLICY (default "parent,children") does the wtx command to send something like "# Notification from another agent: on branch #branch, commit <xyz> was just created with commit message <abc>, merge it by running git merge <xyz>". "#" is important so it gets parsed as comment by bash/zsh.
- wtx prune prunes worktrees + tmuxes + guis that are prunable (where worktree has been deleted), if the branch is of the form wtx/ it deletes the wtx branch too (outputs "deleting/not deleting branch because it was not created/created by wtx)