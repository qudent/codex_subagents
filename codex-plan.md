Yes—got you. Let’s wire your launcher to Codex CLI and expose “spawn subtask” as a tool the model can call via MCP. Here’s a compact, drop-in setup for macOS (zsh) with citations at the end.

⸻

1) Install & sign in to Codex CLI

# Pick one:
npm i -g @openai/codex
# or
brew install codex

# First run opens sign-in (ChatGPT Plus/Team/Enterprise works)
codex

Codex has a non-interactive exec mode and loads AGENTS.md as project memory; it also supports MCP servers declared in ~/.codex/config.toml.  ￼

⸻

2) Save the agent helpers (zsh)

Put this file at ~/.codex/agents.zsh and source it from your shell (or your .zshrc). It creates:
	•	a unique branch + worktree per task,
	•	appends a Task block to AGENTS.md (the thing Codex reads),
	•	spawns Codex CLI in a new Terminal window running a light watch loop using codex exec headlessly,
	•	utilities to await completion and merge back.

# ~/.codex/agents.zsh
set -euo pipefail

_applescript_escape(){ sed 's/\\/\\\\/g; s/"/\\"/g'; }

agent_spawn(){
  git rev-parse --is-inside-work-tree >/dev/null || { echo "Not in a git repo"; return 1; }
  local desc="${*:-(no description)}"
  local repo_root prev_branch ts rnd slug branch worktree now_iso
  repo_root="$(git rev-parse --show-toplevel)"
  prev_branch="$(git rev-parse --abbrev-ref HEAD)"
  ts="$(date +%Y%m%d-%H%M%S)"
  rnd="$(LC_ALL=C tr -dc 'a-f0-9' </dev/urandom | head -c6)"
  slug="$(printf '%s' "$desc" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9- ' | tr ' ' '-' | sed 's/--*/-/g' | cut -c1-32)"
  [[ -z "$slug" ]] && slug="task"
  branch="agent/${slug}-${ts}-${rnd}"
  worktree="${repo_root}/.worktrees/${branch}"

  mkdir -p "${repo_root}/.worktrees"
  git -C "$repo_root" worktree add -b "$branch" "$worktree" HEAD

  local agents="$worktree/AGENTS.md"
  [[ -f "$agents" ]] || : > "$agents"
  now_iso="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  cat >> "$agents" <<EOF

## Task $branch
- Created: $now_iso
- Parent branch: $prev_branch
- Status: pending
- Description:
$desc

- Agent contract:
  1) Work ONLY in this worktree/branch: \`$branch\`.
  2) Keep THIS section’s **Status** updated (pending → working → success/failed/confused + short note).
  3) On success: **commit with message exactly**: \`task $branch finished\`.
  4) Then merge into \`$prev_branch\` (fast-forward or leave PR instructions).
  5) On failure/confusion: set Status accordingly and **ask the user** with concrete questions; do NOT merge.
  6) Small, reversible commits; tests/docs if applicable.
EOF

  ( cd "$worktree" && git add AGENTS.md && git commit -m "chore(agent): register $branch task" >/dev/null )

  # Run Codex CLI in a new Terminal window, headless loop until completion commit appears.
  # Uses `codex exec` (non-interactive). You can silence TUI noise with CODEX_QUIET_MODE.
  local run='
    set -e
    cd '"$worktree"'
    export CODEX_QUIET_MODE=1
    echo "Subagent running for: '"$branch"' (worktree: $(pwd))"
    while true; do
      # Ask Codex to continue the task using AGENTS.md as memory.
      codex exec "Continue working on task '"$branch"'. Follow AGENTS.md contract; update Status; stop only when done or blocked."
      # Pull any upstream updates and check for the finish commit
      git pull --ff-only >/dev/null 2>&1 || true
      if git log --grep="^task '"$branch"' finished$" -1 --pretty=format:%H >/dev/null 2>&1; then
        echo "Completion commit detected. Exiting Codex loop."
        break
      fi
      sleep 60
    done
  '
  local run_esc; run_esc="$(printf '%s' "$run" | _applescript_escape)"
  /usr/bin/osascript >/dev/null <<APPLESCRIPT
tell application "Terminal" to do script "$run_esc"
APPLESCRIPT

  echo "$branch"
}

agent_status(){
  local branch="$1"
  local repo_root agents; repo_root="$(git rev-parse --show-toplevel)"
  agents="$repo_root/.worktrees/$branch/AGENTS.md"
  [[ -f "$agents" ]] || { echo "No AGENTS.md for $branch"; return 1; }
  awk -v b="## Task $branch" '
    $0==b {insec=1; next}
    insec && /^## / {exit}
    insec && $1=="-" && $2=="Status:"{print; exit}
  ' "$agents"
}

agent_await(){
  local branch="$1"
  local repo_root wt agents; repo_root="$(git rev-parse --show-toplevel)"
  wt="$repo_root/.worktrees/$branch"
  agents="$wt/AGENTS.md"
  [[ -d "$wt/.git" ]] || { echo "No such worktree: $wt"; return 1; }
  local parent; parent="$(awk -v b="## Task $branch" '$0==b{in=1;next} in&&/^## /{exit} in&&$1=="-"&&$2=="Parent"&&$3=="branch:"{print $4;exit}' "$agents")"
  [[ -n "${parent:-}" ]] || { echo "Parent branch not found"; return 1; }

  echo "⏳ Waiting for 'task $branch finished'… (parent: $parent)"
  while true; do
    (cd "$wt" && git pull --ff-only >/dev/null 2>&1 || true)
    if (cd "$wt" && git log --grep="^task $branch finished$" -1 --pretty=format:%H >/dev/null 2>&1); then
      echo "✅ Completion detected."
      break
    fi
    printf "\r%s | %s" "$(date '+%H:%M:%S')" "$(agent_status "$branch" 2>/dev/null || echo '- Status: unknown')"
    sleep 5
  done

  echo; echo "🔀 Merging $branch → $parent (ff-only)…"
  (
    cd "$repo_root"
    git fetch -q || true
    cur="$(git rev-parse --abbrev-ref HEAD)"
    trap 'git checkout -q "$cur" || true' EXIT
    git checkout -q "$parent"
    if git merge --ff-only "$branch"; then
      echo "✅ Merged into $parent."
    else
      echo "⚠️ Couldn’t fast-forward. Open a PR or resolve manually."
    fi
  )
  echo "🧹 Cleanup when ready: git worktree remove \"$wt\" && git branch -d \"$branch\""
}

agent_watch_all(){
  local repo_root; repo_root="$(git rev-parse --show-toplevel)"
  while true; do
    echo "---- $(date '+%H:%M:%S') ----"
    git worktree list --porcelain | awk "/worktree / && \$2 ~ /\.worktrees\/agent\// {print \$2}" | while read -r wt; do
      local b; b="${wt#${repo_root}/.worktrees/}"
      (cd "$wt" && git pull --ff-only >/dev/null 2>&1 || true)
      echo "$b  |  $(agent_status "$b" 2>/dev/null || echo '- Status: unknown')"
    done
    sleep 10
  done
}

Usage

source ~/.codex/agents.zsh
# spawn a task into a new branch/worktree + background Codex
agent_spawn "Implement feature X with tests and docs"

# watch all agents
agent_watch_all

# wait for one to finish & merge
agent_await agent/implement-feature-x-20250924-123456-abc123

Notes: codex exec is the non-interactive/headless mode. You can quiet it via CODEX_QUIET_MODE=1.  ￼

⸻

3) Let Codex call subtasks as tools (MCP)

We’ll expose spawn_subagent as an MCP tool so Codex can self-spawn children. Create a tiny Node MCP server:

mkdir -p ~/.codex/mcp && cd ~/.codex/mcp
npm init -y && npm i @modelcontextprotocol/sdk

~/.codex/mcp/subagents.mjs:

#!/usr/bin/env node
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
const execFileP = promisify(execFile);

const server = new McpServer({
  name: "subagents",
  version: "0.1.0",
});

server.tool(
  {
    name: "spawn_subagent",
    description: "Create a new subtask branch/worktree and start Codex there.",
    inputSchema: {
      type: "object",
      properties: { description: { type: "string" } },
      required: ["description"],
    },
  },
  async ({ description }) => {
    // Ensure your zsh functions are available:
    // source ~/.codex/agents.zsh; agent_spawn "desc"
    const cmd = "zsh";
    const args = ["-lc", `source ~/.codex/agents.zsh; agent_spawn ${(JSON.stringify(description))}`];
    const { stdout } = await execFileP(cmd, args, { cwd: process.cwd(), env: process.env });
    const branch = stdout.trim();
    return {
      content: [
        {
          type: "text",
          text: JSON.stringify({ branch }, null, 2),
        },
      ],
    };
  }
);

const transport = new StdioServerTransport();
server.connect(transport).catch((e) => {
  console.error("MCP server failed:", e);
  process.exit(1);
});

Make it executable:

chmod +x ~/.codex/mcp/subagents.mjs

Register it with Codex CLI:

mkdir -p ~/.codex
cat > ~/.codex/config.toml <<'TOML'
[mcp_servers.subagents]
command = "node"
args = ["~/.codex/mcp/subagents.mjs"]
TOML

Now inside Codex you (or the model) can call the tool:
	•	Name: spawn_subagent
	•	Input: { "description": "…task details…" }

Codex detects MCP servers via ~/.codex/config.toml, and MCP is officially supported. Third-party guides show this exact config flow.  ￼

⸻

4) What changed vs. your original snippet
	•	Uses Codex CLI in non-interactive exec mode in a background loop so the task progresses without you babysitting.  ￼
	•	The task contract lives in AGENTS.md, which Codex reads as project memory (no extra prompting needed).  ￼
	•	Adds an MCP tool (spawn_subagent) so the model can itself fork further subtasks (“agents as tools”).  ￼

⸻

Handy one-liners
	•	Spawn:
agent_spawn "Refactor auth middleware; add rate-limit tests; keep API stable"
	•	Wait & merge:
agent_await <branch-name>
	•	Watch all:
agent_watch_all

⸻

Sources
	•	Codex CLI docs: exec (non-interactive), image flag, basics.  ￼
	•	OpenAI Codex CLI repo (install, AGENTS.md memory, MCP support).  ￼
	•	Non-interactive/CI & quiet mode examples.  ￼
	•	MCP config for Codex (config.toml examples/guides).  ￼

If you want, I can also add a “spawn_from_PR” MCP tool (take PR URL → create task with context) and a “cleanup_agent” tool (prune merged worktrees).