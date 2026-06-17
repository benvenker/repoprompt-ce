#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(pwd)}"
grep -q "op=wait alias" "$ROOT/Sources/RepoPromptHeadlessServer/HeadlessToolSchemas.swift"
grep -q "Progress-friendly client wait deadline" "$ROOT/Sources/RepoPromptHeadlessServer/HeadlessToolSchemas.swift"
grep -q "original result shape" "$ROOT/Sources/RepoPromptHeadlessServer/HeadlessToolSchemas.swift"
grep -q "running lifecycle snapshot" "$ROOT/Sources/RepoPromptHeadlessServer/HeadlessToolSchemas.swift"
