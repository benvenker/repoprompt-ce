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

[[ "$(uname -s)" == "Linux" ]] || fail "headless Linux artifacts must be built on Linux"

machine="$(uname -m)"
case "$machine" in
    x86_64 | amd64)
        artifact_arch="x86_64"
        ;;
    *)
        fail "unsupported Linux artifact architecture: $machine"
        ;;
esac

require_command swift
require_command python3
require_command tar
require_command sha256sum

PRODUCT="rpce-headless"
ARTIFACT_VERSION="${MARKETING_VERSION}-${BUILD_NUMBER}"
ARTIFACT_NAME="${PRODUCT}-${ARTIFACT_VERSION}-linux-${artifact_arch}"
SCRATCH_PATH="${RPCE_HEADLESS_SCRATCH_PATH:-$ROOT_DIR/.build-linux-release}"
DIST_DIR="${RPCE_HEADLESS_DIST_DIR:-$ROOT_DIR/dist}"
STAGE_DIR="$DIST_DIR/$ARTIFACT_NAME"
TARBALL="$DIST_DIR/$ARTIFACT_NAME.tar.gz"
SHA_FILE="$TARBALL.sha256"
MANIFEST="$DIST_DIR/$ARTIFACT_NAME-manifest.json"
BINARY="$SCRATCH_PATH/release/$PRODUCT"

printf '==> Building %s for linux-%s\n' "$PRODUCT" "$artifact_arch"
swift build \
    -c release \
    --static-swift-stdlib \
    --product "$PRODUCT" \
    --scratch-path "$SCRATCH_PATH"

[[ -x "$BINARY" ]] || fail "expected executable not found: $BINARY"

printf '==> Running headless MCP smoke\n'
python3 "$ROOT_DIR/Sources/RepoPromptHeadlessServer/Scripts/mcp_smoke.py" "$BINARY" "$ROOT_DIR"

printf '==> Staging %s\n' "$ARTIFACT_NAME"
rm -rf "$STAGE_DIR" "$TARBALL" "$SHA_FILE" "$MANIFEST"
mkdir -p "$STAGE_DIR/bin" "$STAGE_DIR/examples"
install -m 0755 "$BINARY" "$STAGE_DIR/bin/$PRODUCT"
install -m 0644 "$ROOT_DIR/Sources/RepoPromptHeadlessServer/README.md" "$STAGE_DIR/README.md"
install -m 0644 "$ROOT_DIR/Sources/RepoPromptHeadlessServer/Examples/rpce-headless.env" "$STAGE_DIR/examples/rpce-headless.env"
install -m 0644 "$ROOT_DIR/Sources/RepoPromptHeadlessServer/Examples/rpce-headless.service" "$STAGE_DIR/examples/rpce-headless.service"
install -m 0644 "$ROOT_DIR/LICENSE" "$STAGE_DIR/LICENSE"
install -m 0644 "$ROOT_DIR/THIRD_PARTY_NOTICES.md" "$STAGE_DIR/THIRD_PARTY_NOTICES.md"
cp -R "$ROOT_DIR/ThirdPartyLicenses" "$STAGE_DIR/ThirdPartyLicenses"

printf '==> Creating tarball\n'
mkdir -p "$DIST_DIR"
tar -C "$DIST_DIR" -czf "$TARBALL" "$ARTIFACT_NAME"
(cd "$DIST_DIR" && sha256sum "$(basename "$TARBALL")" >"$(basename "$SHA_FILE")")

python3 - "$MANIFEST" "$ARTIFACT_NAME" "$ARTIFACT_VERSION" "$artifact_arch" "$TARBALL" "$SHA_FILE" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

manifest_path = Path(sys.argv[1])
artifact_name = sys.argv[2]
version = sys.argv[3]
arch = sys.argv[4]
tarball = Path(sys.argv[5])
sha_file = Path(sys.argv[6])

payload = {
    "artifact": artifact_name,
    "product": "rpce-headless",
    "version": version,
    "platform": "linux",
    "architecture": arch,
    "staticSwiftStdlib": True,
    "target": "Ubuntu 24.04 / glibc-compatible linux-x86_64",
    "tarball": tarball.name,
    "sha256File": sha_file.name,
    "sha256": hashlib.sha256(tarball.read_bytes()).hexdigest(),
    "contents": [
        "bin/rpce-headless",
        "examples/rpce-headless.env",
        "examples/rpce-headless.service",
        "README.md",
        "LICENSE",
        "THIRD_PARTY_NOTICES.md",
        "ThirdPartyLicenses/",
    ],
}
manifest_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

printf 'Created: %s\n' "$TARBALL"
printf 'Created: %s\n' "$SHA_FILE"
printf 'Created: %s\n' "$MANIFEST"
