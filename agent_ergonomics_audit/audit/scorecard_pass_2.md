# rpce-headless Agent-Ergonomics Scorecard Pass 2

Date: 2026-06-16
Mode: full
Target: `/data/projects/repoprompt-ce`

## Summary

Median scored surface: approximately 850/1000.

This pass applied all six recommendations from the baseline audit. The biggest
first-try gaps are now covered by in-tool self-documentation, successful help,
structured loaded-root metadata, explicit Context Builder examples, a blessed
read-only subagent workflow, and fallback guidance for missing codemaps.

## Findings

| Surface | Pre | Post | Status |
|---|---:|---:|---|
| CLI help | 455 | 875 | Complete: top-level and subcommand help exit 0; typo hint for `--json` |
| Root defaulting | 806 | 875 | Complete: `dump --json`, `workspace_context`, and capabilities expose roots |
| MCP tool exposure | 768 | 850 | Complete: discovery-safe `headless_capabilities` added and smoked |
| context_builder | 768 | 850 | Complete: schema/docs now teach sync, async, timeout, result, cleanup |
| agent_manage / agent_run | 706 | 825 | Complete: tool descriptions, robot docs, README, AGENTS encode preferred flow |
| Discover prompt | 793 | 793 | Unchanged: already strong |
| get_code_structure | 536 | 775 | Complete: no-codemap result now names `file_search` and `read_file` fallback |
| capabilities / robot-docs | 361 | 900 | Complete: CLI and MCP self-documentation contract added |

## Blockers

- P0: none.
- P1: none remaining from the baseline six recommendations.
- P2: remaining polish is optional: richer structured `get_code_structure` fallback payloads and deeper root objects instead of path strings.

## Validation

- Docker `swift build --product rpce-headless --scratch-path .build-linux`: pass.
- CLI contract smoke: pass.
- MCP stdio smoke: pass.
- Socket auth smoke: pass.
- Agent MCP smoke: pass.
- Agent lifecycle smoke: pass.
- CLI Context Builder fake-agent smoke: pass.
- MCP Context Builder fake-agent smoke: pass.
- Audit regression wrappers: pass inside `swift:6.2.4-noble`.
- `git diff --check -- ':!docs/ideation/**'`: pass.

Note: host execution of `.build-linux/debug/rpce-headless` is unsupported on
this Linux host because the debug binary expects Swift runtime libraries from
the Docker image. Run smokes inside `swift:6.2.4-noble` or install the static
artifact with `make headless-linux-install-local`.
