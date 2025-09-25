#!/usr/bin/env node
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { z } from "zod";

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
  try {
    const { stdout } = await execFileP(cmd, ["-lc", shellCommand], {
      cwd: process.cwd(),
      env: process.env,
    });
    return stdout.trim();
  } catch (error) {
    const stderr = error?.stderr?.trim();
    const message = stderr ? `${error.message}: ${stderr}` : error.message;
    throw new Error(`Failed to run ${functionName}: ${message}`);
  }
}

server.registerTool(
  "spawn_subagent",
  {
    description: "Create a new subtask branch/worktree and start Codex there.",
    inputSchema: {
      description: z
        .string()
        .trim()
        .min(1, "Provide a short task summary.")
        .describe("Task summary recorded in AGENTS.md"),
    },
  },
  async ({ description }) => {
    const safeDescription = description?.trim() || "(no description)";
    const branch = await runZshFunction("agent_spawn", [safeDescription]);
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

server.registerTool(
  "cleanup_subagent",
  {
    description: "Remove a finished subagent worktree and branch.",
    inputSchema: {
      branch: z
        .string()
        .trim()
        .min(1, "Branch name is required.")
        .describe("Subagent branch to clean up"),
    },
  },
  async ({ branch }) => {
    const safeBranch = branch.trim();
    const output = await runZshFunction("agent_cleanup", [safeBranch]);
    return {
      content: [
        {
          type: "text",
          text: output || `cleanup requested for ${safeBranch}`,
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
