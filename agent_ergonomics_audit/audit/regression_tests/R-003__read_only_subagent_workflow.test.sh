#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(pwd)}"
BINARY="${RPCE_HEADLESS_BINARY:-$ROOT/.build-linux/debug/rpce-headless}"
"$BINARY" robot-docs guide >/tmp/rpce-robot-docs.out
grep -q "agent_manage" /tmp/rpce-robot-docs.out
grep -q "agent_run" /tmp/rpce-robot-docs.out
grep -q "cleanup_sessions" /tmp/rpce-robot-docs.out
