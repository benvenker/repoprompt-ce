# Agent-Ergonomics Pass 2 Handoff

Full pass completed on 2026-06-16.

## Applied

- R-001: Added CLI `capabilities --json`, CLI `robot-docs guide`, and MCP `headless_capabilities`.
- R-002: Made top-level and subcommand help exit 0 and write useful stdout help.
- R-003: Encoded the preferred Context Builder plus read-only `agent_run` onboarding workflow in capabilities, robot docs, tool descriptions, README, and AGENTS.md.
- R-004: Added `get_code_structure` fallback guidance to `file_search` and `read_file` when codemaps are unavailable.
- R-005: Added loaded-root metadata to `workspace_context`, `dump --json`, and capabilities.
- R-006: Enriched `context_builder` schema descriptions with lifecycle and timeout semantics.

## Key Files

- `Sources/RepoPromptHeadlessServer/main.swift`
- `Sources/RepoPromptHeadlessServer/HeadlessCapabilities.swift`
- `Sources/RepoPromptHeadlessServer/HeadlessToolSchemas.swift`
- `Sources/RepoPromptHeadlessServer/HeadlessMCPServer.swift`
- `Sources/RepoPromptHeadlessServer/HeadlessWorkspaceHost.swift`
- `Sources/RepoPromptHeadlessServer/HeadlessTypes.swift`
- `Sources/RepoPromptHeadlessServer/Scripts/cli_contract_smoke.py`
- `Tests/RepoPromptTests/MCP/HeadlessCLIParserTests.swift`
- `Tests/RepoPromptTests/MCP/HeadlessWorkspaceHostTests.swift`
- `Tests/RepoPromptTests/MCP/HeadlessAgentToolSchemaTests.swift`

## Validation

- `docker run --rm -v "$PWD":/src -w /src swift:6.2.4-noble swift build --product rpce-headless --scratch-path .build-linux`: pass.
- Docker CLI/MCP/socket smokes: pass.
- Docker agent/context-builder smokes: pass.
- Audit regression wrappers: pass inside `swift:6.2.4-noble`.
- `git diff --check -- ':!docs/ideation/**'`: pass.

The full XCTest target was not run on Linux because it pulls macOS-only app
dependencies (`SwiftUI`, `CoreLocation`). Product-only `rpce-headless` build
and headless smokes are the valid Linux proof for this pass.

## Remaining Follow-Up

- Consider a true `--robot-triage` mega-command in a later pass.
- Consider structured `get_code_structure` fallback payloads with unmapped path metadata.
- Consider richer root objects (`id`, `name`, `full_path`) instead of path strings only.

No P0/P1 blockers remain from the initial audit.
