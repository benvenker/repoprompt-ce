#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(pwd)}"
BINARY="${RPCE_HEADLESS_BINARY:-$ROOT/.build-linux/debug/rpce-headless}"
"$BINARY" robot-docs status --json | python3 -c 'import json,sys; p=json.load(sys.stdin); assert p["tool_name"] == "rpce-headless"; assert p["loaded_root_metadata"]; assert p["suggested_first_tool_calls"][0] == "headless_status"; assert "context_builder" in p["suggested_first_tool_calls"][1]; assert p["architecture_onboarding"]["preferred_summary_tool"] == "context_builder"'
"$BINARY" capabilities --json | python3 -c 'import json,sys; p=json.load(sys.stdin); assert "headless_status" in p["recommended_workflow"][0]; assert "headless_capabilities" in p["recommended_workflow"][1]; assert p["architecture_onboarding"]["preferred_summary_tool"] == "context_builder"'
