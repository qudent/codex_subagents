**wtx — spin up a new place to work, fast**

- Do this: `wtx create`
- A new terminal opens with that worktree/session ("auto‑attaches").
- Run `wtx create` again to get another one and work in parallel.
- Under the hood it’s using tmux for the terminals, but you don’t need to know tmux to use it.

**Why**
- Try multiple approaches (cheap vs. expensive models, different prompts) side‑by‑side.
- Keep each attempt isolated in its own branch + folder.
- Send quick messages/commands between attempts when needed.

**Install**
- Requirements: bash, git, tmux; macOS or Linux. Optional: Node/npm.
- Install tmux: `brew install tmux` (macOS) or `sudo apt-get install tmux` (Debian/Ubuntu).
- Put `wtx` on your PATH: `chmod +x wtx && cp wtx /usr/local/bin/`
- macOS: a new Terminal window opens when you create a worktree (set `WTX_OSA_OPEN=0` to disable).
- Linux/servers: the session is created; attach with `wtx open` or `tmux attach -t wtx:<branch>`.

**Quickstart**
- From any Git repo:
  - `wtx create` → makes a branch and worktree and opens a new terminal there.
  - Do it again to explore another idea in parallel.
- Optional: add a description with `-d` (e.g., `wtx create -d login-flow`).
- List: `wtx list` • Remove: `wtx remove <branch>` • Reopen: `wtx open`
  - Remove with untracked/modified files: `wtx remove --force <branch>`

**What actually happens**
- New Git branch (like `sNNN-PARENT[-slug]`).
- New Git worktree folder under `<repo>.worktrees/`.
- New tmux session bound to that folder; your terminal opens in it.
- `.venv` and `.env` are linked if present; env vars exported; `npm ci`/`npm install` runs if needed.

**Talking between attempts (optional)**
- Parent → children: `wtx notify_children --keys "git pull --ff-only && npm test"`
- Child → parent: `wtx notify_parents --keys "printf 'done!\n' >> wtx_msgs.log"`

**Defaults and config**
- Today, `-p` (parent branch) defaults to `main`. You can pass `-p <branch>` to override.
- `WTX_SESSION_PREFIX` (default `wtx`), `WTX_OSA_OPEN` (macOS: `1` to open Terminal),
  `WTX_SHORT_PREFIX` (default `s`), `WTX_CONTAINER_DEFAULT` (override `<repo>.worktrees`).

**Heads‑up**
- We plan to make the default parent “the branch you’re currently on” instead of `main` (see TODO.md).
- Tiny tmux primer: it’s just a terminal that keeps running. Attach: `tmux attach -t wtx:<branch>`; detach: `Ctrl+B`, then `D`.

**License**
MIT (see repository).
