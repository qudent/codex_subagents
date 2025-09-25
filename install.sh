#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_DIR="${HOME}/.codex"
MCP_DIR="${CODEX_DIR}/mcp"
TARGET_AGENT="${CODEX_DIR}/agents.zsh"
TARGET_MCP="${MCP_DIR}/subagents.mjs"
TARGET_PACKAGE="${MCP_DIR}/package.json"
CONFIG_FILE="${CODEX_DIR}/config.toml"
SNIPPET_FILE="${SCRIPT_DIR}/config/config.toml"
SNIPPET_CONTENT="$(sed "s|{{TARGET_MCP}}|${TARGET_MCP}|g" "${SNIPPET_FILE}")"

mkdir -p "${CODEX_DIR}" "${MCP_DIR}" "${CODEX_DIR}/backups"

if [[ -f "${TARGET_AGENT}" ]]; then
  cp "${TARGET_AGENT}" "${CODEX_DIR}/backups/agents.zsh.$(date +%Y%m%d-%H%M%S)"
  echo "Backed up existing agents.zsh"
fi

install -m 0644 "${SCRIPT_DIR}/scripts/agents.zsh" "${TARGET_AGENT}"
install -m 0755 "${SCRIPT_DIR}/mcp/subagents.mjs" "${TARGET_MCP}"

echo "Wrote ${TARGET_AGENT}"
echo "Wrote ${TARGET_MCP}"

if [[ -f "${TARGET_PACKAGE}" ]]; then
  echo "Keeping existing package.json"
else
  cp "${SCRIPT_DIR}/mcp/package.json" "${TARGET_PACKAGE}"
  echo "Wrote ${TARGET_PACKAGE}"
fi

if [[ -f "${CONFIG_FILE}" ]]; then
  if grep -q "\[mcp_servers.subagents\]" "${CONFIG_FILE}"; then
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
echo "  1) source ~/.codex/agents.zsh   (or add to ~/.zshrc)"
echo "  2) Run 'codex' once to sign in if you have not already"
echo "  3) cd ~/.codex/mcp && npm install"
echo "  4) Use agent_spawn / agent_await / agent_watch_all / agent_cleanup"
