#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(pwd)}"
BINARY="${RPCE_HEADLESS_BINARY:-$ROOT/.build-linux/debug/rpce-headless}"
python3 "$ROOT/Sources/RepoPromptHeadlessServer/Scripts/mcp_smoke.py" "$BINARY" "$ROOT"
