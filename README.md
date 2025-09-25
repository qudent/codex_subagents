# Codex Subagents Toolkit

A minimal macOS-friendly starter kit that turns the plan in `codex-plan.md` into a GitHub-ready repository. It wires Codex CLI to spawn per-task worktrees, keeps AGENTS.md up to date, launches a visible Terminal session for each subagent, and exposes subagent tools over MCP.

## Prerequisites
- macOS with zsh (default on modern macOS)
- Git 2.38+
- Node.js 18+ (for the MCP server)
- Codex CLI (`npm i -g @openai/codex` or `brew install codex`) and a signed-in session (`codex` on first run)

## Install
```bash
./install.sh
# follow the next steps printed at the end
```
The installer copies the helper scripts into `~/.codex`, backs up any existing `agents.zsh`, ensures the MCP server is executable, and appends the MCP config block if it is missing.
> Heads-up: the Codex CLI does not expand `~` inside MCP server paths. Re-running `./install.sh` after pulling updates refreshes `~/.codex/config.toml` with the correct absolute path automatically.

Source the helpers for your current shell and future sessions:
```bash
source ~/.codex/agents.zsh
# optionally add the same line to ~/.zshrc
```
The helper preserves your existing `set -o` strict-mode choices, so sourcing it won't leave options like `nounset` enabled unexpectedly—a common cause of `RPROMPT: parameter not set` errors in customized prompts.

## Usage
You now have two ways to drive subagents:

1. Source `scripts/agents.zsh` (or `~/.codex/agents.zsh` after running `./install.sh`) to get the lightweight `agent_*` zsh helpers.
2. Run the new dual-shell script `scripts/agent.sh`, which works the same under bash or zsh and exposes structured subcommands.

### scripts/agent.sh (recommended for automation)
```bash
scripts/agent.sh spawn "Describe the task for Codex"
```
- Creates a dedicated branch & worktree under `.worktrees/<timestamp>-<rand>`
- Prefers `direnv` for secrets; falls back to a sanitized whitelist from `scripts/agent.env.example`
- Launches Codex in a detached tmux session and, on macOS, opens a Terminal window attached to it (configurable via `AGENT_MAC_ATTACH`)
- Prints the task id, worktree path, and `tmux attach` command for manual supervision

Other handy subcommands:
- `scripts/agent.sh list` — enumerate active `codex-*` tmux sessions
- `scripts/agent.sh attach <task-id>` — attach to the session
- `scripts/agent.sh reload-env <task-id>` — run `direnv reload` or re-export whitelisted vars
- `scripts/agent.sh status <task-id>` — show branch/worktree/session health
- `scripts/agent.sh cleanup <task-id> [--force]` — tear down the session, worktree, and branch

Configuration lives next to the script:
- `scripts/agent.conf` — optional overrides (e.g., `AGENT_ENV_MODE=whitelist`, `AGENT_MAC_ATTACH=0`)
- `scripts/agent.env.example` — document + curate the whitelist that the fallback exporter honors; set `AGENT_ENV_FILE` if you keep a different manifest, or export variables in your shell before spawning

### agents.zsh helpers (interactive shell sugar)
- `agent_spawn "Describe the task"`
  - Wraps `agent.sh spawn` and keeps the legacy contract with `AGENTS.md`
- `agent_await agent/refactor-foo-...`
  - Polls the worktree, reports status lines from `AGENTS.md`, merges back into the parent when the completion commit appears, and reminds you to clean up
- `agent_watch_all`
  - Lists active agent worktrees and their status every 10 seconds
- `agent_cleanup agent/refactor-foo-... [--force]`
  - Removes the extra worktree and branch. Pass `--force` if unpushed commits or dirty state need to be discarded.

### MCP tools
The repository ships a small MCP server (`subagents.mjs`) registered as `spawn_subagent` and `cleanup_subagent`. Codex can now call these tools directly when working in a project configured with this repo’s helpers.

## Repository Layout
- `install.sh` – bootstrap script that installs helpers into `~/.codex`
- `scripts/agents.zsh` – zsh functions (`agent_spawn`, `agent_await`, `agent_watch_all`, `agent_cleanup`)
- `mcp/subagents.mjs` – Node-based MCP server exposing `spawn_subagent` / `cleanup_subagent`
- `config/config.toml` – snippet appended to `~/.codex/config.toml`
- `codex-plan.md` – original specification

## Uninstall
Remove the worktree helpers and MCP server:
```bash
rm ~/.codex/agents.zsh
rm ~/.codex/mcp/subagents.mjs
# optionally edit ~/.codex/config.toml to drop the [mcp_servers.subagents] block
```
Clean up any `.worktrees/agent/...` directories per project via `agent_cleanup` or `git worktree remove`.

---
Questions or enhancements? Open an issue or tweak locally—this repo is intentionally simple so you stay in control.
