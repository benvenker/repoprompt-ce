# Pass 2 Uplift

| Surface | Pre | Post | Delta |
|---|---:|---:|---:|
| CLI help | 455 | 875 | +420 |
| Root defaulting | 806 | 875 | +69 |
| MCP tool exposure | 768 | 850 | +82 |
| context_builder | 768 | 850 | +82 |
| agent_manage / agent_run | 706 | 825 | +119 |
| Discover prompt | 793 | 793 | +0 |
| get_code_structure | 536 | 775 | +239 |
| capabilities / robot-docs | 361 | 900 | +539 |

Median scored surface moved from approximately 737/1000 to approximately
850/1000. No scored surface regressed.

## Pass 3 Functional Follow-Up

Pass 3 was intentionally functional-first rather than a full skill-guided
rescore. It applied three queued follow-ups from the pass-2 handoff:

- Added compact status JSON through CLI `robot-docs status --json` and MCP
  `headless_status`.
- Added `loaded_root_metadata` and `root_warnings` to structured root-bearing
  replies while keeping `loaded_roots` stable.
- Added structured `get_code_structure` no-codemap evidence with
  `codemap_unavailable` and fallback tools `file_search` plus `read_file`.
- Reconciled architecture-onboarding guidance around the intended order:
  `headless_status`, then `context_builder` synthesis, then direct
  tree/search/code-structure/read_file calls for verification and citations.
- After black-box skill-climb testing, promoted `context_builder`,
  `agent_manage`, and `agent_run` in MCP `tools/list` order/descriptions so
  agents see `headless_status`, then the fuller capabilities contract, then
  curated discovery and the optional server-managed subagent lifecycle before
  defaulting to repeated file reads.
- Exposed native RepoPrompt workflow shapes through `native_workflows` in
  status/capabilities and robot docs: role labels, scoped-subagent rules, and
  investigate/optimize/deep_plan composition patterns separate from Smithers.
  The same block records `custom_workflows` as a headless extension point with
  current support marked `metadata_only`.
- Fixed the observed Context Builder trap from Codex session
  `019ed2d2-e725-7280-9e48-4fd26cc6282d`: compatibility calls now create a
  pollable async run, return a `context_id` before MCP client timeouts, and
  accept `context_id:"active"` for recovery. The contract now states the
  omitted-`op` response is union-shaped: original result shape when the run
  completes inside the sync cap, lifecycle snapshot when it does not.
- Fixed the follow-up Context Builder progress trap from Codex session
  `019ed2df-a02a-72d2-9bc5-4914647f39c4`: `op:"wait"` now accepts
  `timeout_seconds` as an alias, caps waits to progress-friendly windows,
  honors `timeout` over `timeout_seconds`, emits MCP progress-token
  heartbeats, documents the wait-cap override, and includes structured
  elapsed/next-action fields in snapshots.

Run the next audit pass to assign formal post-pass scores for these surfaces.
