#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_DIR="${HOME}/.codex"
MCP_DIR="${CODEX_DIR}/mcp"
TARGET_AGENT_SH="${CODEX_DIR}/agent.sh"
TARGET_MCP="${MCP_DIR}/subagents.mjs"
TARGET_PACKAGE="${MCP_DIR}/package.json"
CONFIG_FILE="${CODEX_DIR}/config.toml"
SNIPPET_FILE="${SCRIPT_DIR}/config/config.toml"
SNIPPET_CONTENT="$(sed "s|{{TARGET_MCP}}|${TARGET_MCP}|g" "${SNIPPET_FILE}")"

mkdir -p "${CODEX_DIR}" "${MCP_DIR}" "${CODEX_DIR}/backups"

if [[ -f "${TARGET_AGENT_SH}" ]]; then
  cp "${TARGET_AGENT_SH}" "${CODEX_DIR}/backups/agent.sh.$(date +%Y%m%d-%H%M%S)"
  echo "Backed up existing agent.sh"
fi

install -m 0755 "${SCRIPT_DIR}/scripts/agent.sh" "${TARGET_AGENT_SH}"
install -m 0755 "${SCRIPT_DIR}/mcp/subagents.mjs" "${TARGET_MCP}"

echo "Wrote ${TARGET_AGENT_SH}"
echo "Wrote ${TARGET_MCP}"

if [[ -f "${TARGET_PACKAGE}" ]]; then
  echo "Keeping existing package.json"
else
  cp "${SCRIPT_DIR}/mcp/package.json" "${TARGET_PACKAGE}"
  echo "Wrote ${TARGET_PACKAGE}"
fi

if [[ -f "${CONFIG_FILE}" ]]; then
  if grep -q "\[mcp_servers.subagents]" "${CONFIG_FILE}"; then
    echo "Config already contains subagents entry"
  else
    printf '\n' >> "${CONFIG_FILE}"
    printf '%s\n' "${SNIPPET_CONTENT}" >> "${CONFIG_FILE}"
    echo "Appended subagents MCP block to ${CONFIG_FILE}"
  fi
else
  printf '%s\n' "${SNIPPET_CONTENT}" > "${CONFIG_FILE}"
  echo "Created ${CONFIG_FILE} with MCP block"
fi

echo "\nNext steps:"
echo "  1) Ensure ~/.codex is in your PATH to use the 'agent.sh' command."
echo "     For example, add 'export PATH=$HOME/.codex:$PATH' to your ~/.zshrc or ~/.bash_profile"
echo "  2) Run 'codex' once to sign in if you have not already"
echo "  3) cd ~/.codex/mcp && npm install"
echo "  4) Use 'agent.sh spawn "your task"' to start an agent."