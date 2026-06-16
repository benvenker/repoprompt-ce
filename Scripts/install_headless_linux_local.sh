#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/version.env"

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

[[ "$(uname -s)" == "Linux" ]] || fail "local headless Linux install must run on Linux"

machine="$(uname -m)"
case "$machine" in
    x86_64 | amd64)
        artifact_arch="x86_64"
        ;;
    *)
        fail "unsupported Linux artifact architecture: $machine"
        ;;
esac

require_command docker
require_command install
require_command python3
require_command sha256sum

PRODUCT="rpce-headless"
ARTIFACT_VERSION="${MARKETING_VERSION}-${BUILD_NUMBER}"
ARTIFACT_NAME="${PRODUCT}-${ARTIFACT_VERSION}-linux-${artifact_arch}"
INSTALL_BIN="${RPCE_HEADLESS_INSTALL_BIN:-$HOME/.local/bin/$PRODUCT}"
STAGED_BIN="$ROOT_DIR/dist/$ARTIFACT_NAME/bin/$PRODUCT"
DOCKER_IMAGE="${RPCE_HEADLESS_SWIFT_DOCKER_IMAGE:-swift:6.2.4-noble}"

printf '==> Building static %s artifact with %s\n' "$PRODUCT" "$DOCKER_IMAGE"
docker run --rm -v "$ROOT_DIR":/src -w /src "$DOCKER_IMAGE" \
    bash -lc 'apt-get update >/dev/null && apt-get install -y python3 >/dev/null && ./Scripts/package_headless_linux.sh'

[[ -x "$STAGED_BIN" ]] || fail "expected staged binary not found: $STAGED_BIN"

install -d -m 0755 "$(dirname "$INSTALL_BIN")"
if [[ -e "$INSTALL_BIN" ]]; then
    backup="$INSTALL_BIN.bak-$(date -u +%Y%m%d%H%M%S)"
    cp -p "$INSTALL_BIN" "$backup"
    printf '==> Backed up existing binary: %s\n' "$backup"
fi

printf '==> Installing %s to %s\n' "$STAGED_BIN" "$INSTALL_BIN"
install -m 0755 "$STAGED_BIN" "$INSTALL_BIN"
sha256sum "$INSTALL_BIN"

printf '==> Verifying installed host binary\n'
python3 "$ROOT_DIR/Sources/RepoPromptHeadlessServer/Scripts/cli_contract_smoke.py" "$INSTALL_BIN" "$ROOT_DIR"
python3 "$ROOT_DIR/Sources/RepoPromptHeadlessServer/Scripts/mcp_smoke.py" "$INSTALL_BIN" "$ROOT_DIR"
python3 "$ROOT_DIR/Sources/RepoPromptHeadlessServer/Scripts/mcp_agent_smoke.py" "$INSTALL_BIN" "$ROOT_DIR"

cat <<EOF

Installed $PRODUCT for local MCP clients.
Restart existing Codex-spawned headless servers for this repo with:

  pkill -TERM -f "$PRODUCT serve --root $ROOT_DIR" || true

EOF
