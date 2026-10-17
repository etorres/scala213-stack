#!/bin/sh
# Start a standalone Metals MCP server for the sbt project in the current directory (or $1),
# on a fixed port so the generated .mcp.json stays valid across restarts.
#
#   METALS_MCP_PORT   port to listen on (default 7333)
#   METALS_MCP_BSP    "bloop" (default) or "sbt" to use the sbt BSP server instead
#
# Usage: scripts/start-metals-mcp.sh [workspace]
set -eu

workspace=${1:-$PWD}
port=${METALS_MCP_PORT:-7333}
bsp=${METALS_MCP_BSP:-bloop}

if ! command -v metals-mcp >/dev/null 2>&1; then
  echo "metals-mcp not found. Install it with: cs install metals-mcp" >&2
  exit 1
fi

if [ ! -f "$workspace/build.sbt" ]; then
  echo "No build.sbt in $workspace: run this from the sbt project root." >&2
  exit 1
fi

set -- --workspace "$workspace" --port "$port" --client claude
if [ "$bsp" = "sbt" ]; then
  set -- "$@" --default-bsp-to-build-tool
fi

echo "Starting Metals MCP on http://localhost:$port/mcp (workspace: $workspace, bsp: $bsp)" >&2
echo "Writes $workspace/.mcp.json for Claude Code. Stop with Ctrl-C." >&2
exec metals-mcp "$@"
