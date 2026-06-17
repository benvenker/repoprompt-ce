# Pass 3 Functional Handoff

Functional pass completed on 2026-06-16. This was not a full opinionated
agent-ergonomics rescore; the next audit pass should judge the result against
the skill rubric.

## Applied

- R-007: Added compact first-call status JSON via
  `rpce-headless robot-docs status --json` and MCP `headless_status`.
  `robot-docs triage --json` is accepted as a compatibility alias.
- R-008: Added structured `get_code_structure` no-codemap evidence:
  resolved file path, `codemap_unavailable`, unresolved paths, and fallback
  tools `file_search` plus `read_file`.
- R-009: Added architecture-onboarding guidance to status JSON,
  capabilities JSON, robot docs, README, and AGENTS.md. The intended order is
  root triage with `headless_status`, then `context_builder` for curated
  synthesis, then direct tree/search/code-structure/read_file tools for
  verification anchors and citations.
- R-010: Promoted advanced MCP discovery after black-box testing showed agents
  still defaulting to file-by-file reads: `context_builder`, `agent_manage`,
  and `agent_run` now appear immediately after `headless_status` and
  `headless_capabilities` in `tools/list`; descriptions name Context Builder
  as the preferred onboarding and planning path and describe
  `agent_manage`/`agent_run` as the rpce-headless server-managed optional
  independent-review lifecycle, not client-local ad hoc subagents.
- Status-first closeout: adjusted `headless_capabilities.recommended_workflow`
  and MCP tool discovery so fresh agents see `headless_status` first,
  `headless_capabilities` second, `context_builder` third, then optional
  server-managed subagent tools before direct file reads.
- R-011: Added `native_workflows` to status/capabilities and robot docs so
  headless agents can see native RepoPrompt product workflow patterns
  separately from Smithers: roles `explore`, `engineer`, `pair`, `design`,
  scoped-subagent composition rules, and investigate/optimize/deep_plan
  choreography. The block also includes `custom_workflows` extension guidance,
  with current headless support marked `metadata_only` until workflow listing,
  resolution, and settings-backed mutation are implemented.
- R-012: Fixed black-box Context Builder recovery. A synchronous compatibility
  call that exceeds the MCP-safe wait cap now returns a running snapshot with a
  real `context_id` instead of letting the client hit its two-minute tool-call
  timeout. Lifecycle calls accept `context_id:"active"`/`"current"` for the
  current run. Compatibility mode is explicitly union-shaped: short completed
  calls keep the original result shape; longer calls return lifecycle
  snapshots.
- R-013: Fixed the next black-box Context Builder progress trap. `op:"wait"`
  now accepts `timeout_seconds` as an alias for the client wait window, caps
  oversized waits to progress-friendly snapshots, emits MCP
  `notifications/progress` heartbeats when the client supplies a progress
  token, documents `RPCE_CONTEXT_BUILDER_WAIT_MAX_SECONDS` for operators that
  truly want longer waits, and returns `started_at`, `elapsed_seconds`, and
  `next_action` in run snapshots.
- R-014: Made `headless_status` transport-aware. Discovery-restricted sockets
  now report only direct evidence tools as available here, avoid suggesting
  full-only `context_builder`/`agent_manage`/`agent_run`/`oracle_send` calls,
  and point agents to full stdio or authenticated full-tool sockets for those
  advanced workflows.
- Context Builder lifecycle recovery: `context_id:"active"` and
  `"current"` now resolve to the active run, or the latest completed run until
  cleanup, so clients can wait to completion and then recover results without
  remembering the UUID. Completed omitted-`op` compatibility calls that return
  the original result shape are cleaned up by the server.
- Extended root metadata beyond bare strings with `loaded_root_metadata` and
  `root_warnings` while preserving the existing `loaded_roots` array.

## Key Files

- `Sources/RepoPromptHeadlessServer/HeadlessTypes.swift`
- `Sources/RepoPromptHeadlessServer/HeadlessCapabilities.swift`
- `Sources/RepoPromptHeadlessServer/HeadlessToolSchemas.swift`
- `Sources/RepoPromptHeadlessServer/HeadlessMCPServer.swift`
- `Sources/RepoPromptHeadlessServer/HeadlessWorkspaceHost.swift`
- `Sources/RepoPromptHeadlessServer/main.swift`
- `Sources/RepoPromptHeadlessServer/Scripts/cli_contract_smoke.py`
- `Sources/RepoPromptHeadlessServer/Scripts/mcp_smoke.py`
- `Sources/RepoPromptHeadlessServer/Scripts/socket_auth_smoke.py`
- `Sources/RepoPromptHeadlessServer/Scripts/context_builder_mcp_fake_agent_test.py`
- `Tests/RepoPromptTests/MCP/HeadlessCLIParserTests.swift`
- `Tests/RepoPromptTests/MCP/HeadlessWorkspaceHostTests.swift`
- `Tests/RepoPromptTests/MCP/HeadlessAgentToolSchemaTests.swift`

## Validation

- `docker run --rm -v "$PWD":/src -w /src swift:6.2.4-noble swift build --product rpce-headless --scratch-path .build-linux`: pass.
- Docker Context Builder MCP fake-agent smoke:
  `python3 Sources/RepoPromptHeadlessServer/Scripts/context_builder_mcp_fake_agent_test.py .build-linux/debug/rpce-headless "$PWD"`:
  pass, including progress-token heartbeat, capped-wait recovery coverage, and
  active/current result recovery after completion.
- Docker general MCP smoke:
  `python3 Sources/RepoPromptHeadlessServer/Scripts/mcp_smoke.py .build-linux/debug/rpce-headless "$PWD"`:
  pass, including status-first `tools/list` prefix.
- Docker CLI contract smoke:
  `python3 Sources/RepoPromptHeadlessServer/Scripts/cli_contract_smoke.py .build-linux/debug/rpce-headless "$PWD"`:
  pass, including status-first capabilities recommended workflow.
- Docker audit regression shell checks `R-006__context_builder_schema_guidance`
  and `R-007__headless_status`: pass, including `headless_status` before
  `headless_capabilities` in the public contract assertions.
- Docker socket auth smoke:
  `python3 Sources/RepoPromptHeadlessServer/Scripts/socket_auth_smoke.py .build-linux/debug/rpce-headless "$PWD"`:
  pass, including transport-aware restricted-socket `headless_status`.
- `git diff --check -- ':!docs/ideation/**'`: pass.
- Focused XCTest target was attempted but is not viable on Linux because the
  package test target pulls macOS-only dependencies (`SwiftUI`,
  `CoreLocation`, and SwiftOpenAI `PlatformImage`). Use product build plus
  headless smokes as Linux proof.

## Next Audit Pass

- Re-score the pass-3 status, root metadata, code-structure fallback, and
  architecture-onboarding/tool-discovery/native-workflow/context-builder
  recovery surfaces.
- Run the skill's full ambition/scorecard loop if a formal uplift number is
  needed.
- Consider whether a top-level `rpce-headless status --json` alias is worth
  adding after observing agent behavior with `robot-docs status --json`.
