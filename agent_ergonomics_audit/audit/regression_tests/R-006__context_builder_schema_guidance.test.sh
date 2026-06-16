#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(pwd)}"
grep -q "timeout_seconds caps the discovery agent lifetime" "$ROOT/Sources/RepoPromptHeadlessServer/HeadlessToolSchemas.swift"
grep -q "Client wait deadline" "$ROOT/Sources/RepoPromptHeadlessServer/HeadlessToolSchemas.swift"
