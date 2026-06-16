#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(pwd)}"
BINARY="${RPCE_HEADLESS_BINARY:-$ROOT/.build-linux/debug/rpce-headless}"
"$BINARY" --help >/tmp/rpce-help.out
grep -q "Usage: rpce-headless" /tmp/rpce-help.out
"$BINARY" serve --help >/tmp/rpce-serve-help.out
grep -q "Usage: rpce-headless serve" /tmp/rpce-serve-help.out
