# Agent-Ergonomics Pass 3 Handoff

Pass 2 completed on 2026-06-16. Pass 3 functional uplift completed afterward,
focused on status-first onboarding, Context Builder recovery/progress, native
workflow visibility, server-managed subagent guidance, and structured root/code
fallback metadata. This was not a full opinionated skill rescore; the next
audit pass should judge these surfaces against the skill rubric.

## Pass 3 Functional Addendum

Functional pass completed on 2026-06-16 after the user asked to prioritize the
functional improvements before a full opinionated skill rescore. See
`agent_ergonomics_audit/pass3_handoff.md` for details.

Applied follow-ups:

- R-007: Added compact status JSON via `robot-docs status --json`, alias
  `robot-docs triage --json`, and MCP `headless_status`.
- R-008: Added structured `get_code_structure` no-codemap fallback evidence.
- R-009: Added first-class architecture onboarding guidance to status,
  capabilities, robot docs, README, and AGENTS.md.
- R-010: Promoted `context_builder`, `agent_manage`, and `agent_run` in MCP
  discovery so agents see curated discovery and server-managed subagents before
  direct file reads on the full stdio surface.
- R-011: Exposed native RepoPrompt workflow metadata separately from Smithers
  workflows, including roles, composition rules, built-in workflow shapes, and
  custom-workflow extension guidance marked `metadata_only` for headless v1.
- R-012: Made Context Builder compatibility calls recoverable when they exceed
  the short MCP-safe wait cap by returning lifecycle snapshots with
  `context_id`; `active`/`current` now target the active run or latest completed
  run until cleanup.
- R-013: Added progress-friendly Context Builder waits: `timeout_seconds` wait
  alias, capped waits, progress notifications when clients provide a progress
  token, elapsed/started metadata, and next-action guidance.
- R-014: Made `headless_status` transport-aware so discovery-restricted sockets
  do not advertise full-only tools as available here or suggest invalid next
  calls; restricted status points agents to direct evidence tools and full
  stdio/authenticated sockets for advanced tools.

The next pass should run the full skill-guided audit/rescore against these new
surfaces instead of assuming uplift from this functional handoff alone.

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
- Consider a top-level `rpce-headless status --json` alias after observing
  whether `robot-docs status --json` is discoverable enough.
- Consider a future headless workflow resolver/settings mutation surface before
  claiming `agent_run workflow_name` support.

No P0/P1 blockers remain from the initial audit.
