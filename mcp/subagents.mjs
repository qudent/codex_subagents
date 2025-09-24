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

async function runZshFunction(functionName, args) {
  const quotedArgs = (args ?? []).map((value) => JSON.stringify(value));
  const cmd = "zsh";
  const invocation = [functionName, ...quotedArgs].join(" ");
  const shellCommand = `source ~/.codex/agents.zsh; ${invocation}`;
  const { stdout } = await execFileP(cmd, ["-lc", shellCommand], {
    cwd: process.cwd(),
    env: process.env,
  });
  return stdout.trim();
}

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
    const branch = await runZshFunction("agent_spawn", [description]);
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

server.tool(
  {
    name: "cleanup_subagent",
    description: "Remove a finished subagent worktree and branch.",
    inputSchema: {
      type: "object",
      properties: { branch: { type: "string" } },
      required: ["branch"],
    },
  },
  async ({ branch }) => {
    const output = await runZshFunction("agent_cleanup", [branch]);
    return {
      content: [
        {
          type: "text",
          text: output || `cleanup requested for ${branch}`,
        },
      ],
    };
  }
);

const transport = new StdioServerTransport();
server.connect(transport).catch((error) => {
  console.error("MCP server failed:", error);
  process.exit(1);
});
