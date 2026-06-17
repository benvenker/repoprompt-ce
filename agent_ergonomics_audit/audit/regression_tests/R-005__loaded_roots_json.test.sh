#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(pwd)}"
BINARY="${RPCE_HEADLESS_BINARY:-$ROOT/.build-linux/debug/rpce-headless}"
"$BINARY" dump --json | python3 -c 'import json,sys; p=json.load(sys.stdin); assert p["loaded_roots"] and p["root_count"] >= 1; assert p["loaded_root_metadata"] and p["loaded_root_metadata"][0]["path"]'
