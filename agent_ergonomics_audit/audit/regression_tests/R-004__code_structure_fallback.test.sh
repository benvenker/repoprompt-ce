#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(pwd)}"
grep -q "Fall back to.*file_search.*read_file" "$ROOT/Sources/RepoPromptHeadlessServer/HeadlessWorkspaceHost.swift"
