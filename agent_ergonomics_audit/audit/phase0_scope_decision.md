# Phase 0 Scope Decision

Date: 2026-06-16

Mode: audit-only.

Target: `/data/projects/repoprompt-ce`, focused on `rpce-headless` and the headless MCP onboarding surface for Codex/Linux agents.

Primary surfaces:
- CLI entry points: `rpce-headless`, `serve`, `dump`, `connect`, `context-build`.
- MCP tools: `workspace_context`, `get_file_tree`, `file_search`, `get_code_structure`, `read_file`, `manage_selection`, `prompt`, `context_builder`, `agent_manage`, `agent_run`, `oracle_send`.
- Agent-facing docs and examples: `AGENTS.md`, `Sources/RepoPromptHeadlessServer/README.md`, `Sources/RepoPromptHeadlessServer/Examples/agents.json`, `Sources/RepoPromptHeadlessServer/Examples/rpce-headless.env`, `Sources/RepoPromptHeadlessServer/Examples/rpce-headless.service`.
- Smoke and lifecycle harnesses under `Sources/RepoPromptHeadlessServer/Scripts/`.
- Session evidence from Codex session `019ed1ee-5769-7d83-ac3b-d4cef962dfed` in `/data/projects/skill-climb`.

Guardrails:
- No code edits.
- No staging, commits, pushes, destructive git, process cleanup, or service restarts.
- No Oracle use unless explicitly requested.
- Use existing Docker/Linux build guidance as evidence; do not install host toolchains.
- Focus on headless Linux/Codex agent ergonomics, not macOS app GUI surfaces.

## Pass 2 Override

Mode: full.

User requested a first applied pass of changes after reviewing the audit. Code
edits are allowed for `rpce-headless`, headless MCP schemas, headless smoke
harnesses, focused tests, and agent-facing docs. Staging, commits, pushes,
destructive git, service restarts, and visible app lifecycle actions remain out
of scope unless separately requested.
