# Plan 012: Headless docs/config/plan-index hygiene (agent tools, env vars, security posture)

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `docs/plans/fable/README.md`.
>
> **Drift check (run first)**: confirm plan 007 is DONE (this plan documents
> its flag/handshake; if 007 is not DONE, STOP). Then
> `git diff --stat 0bd2270..HEAD -- Sources/RepoPromptHeadlessServer/README.md Sources/RepoPromptHeadlessServer/Examples/ docs/plans/fable/`
> Line numbers below were taken at `0bd2270`; re-locate by heading text if
> they shifted.

## Status

- **Priority**: P3
- **Effort**: S
- **Risk**: LOW (docs/config only; no code)
- **Depends on**: plan 007 (required); plans 009/011 (soft — mention their outcomes if landed)
- **Category**: docs
- **Planned at**: commit `0bd2270`, 2026-06-12

## Why this matters

The headless server now ships `agent_run` and `agent_manage`, but the README
never mentions them: the Tools list omits them, the "exposes all tools"
prose names only `oracle_send` and `context_builder`, and none of the four
`RPCE_AGENT_*` env vars are documented anywhere. The example env file seeds
neither the agent vars nor the five documented `RPCE_CONTEXT_BUILDER_*`
vars. The example `agents.json` runs Claude with
`--permission-mode bypassPermissions` with no warning about what that means
on a VPS. And the plan index has gone stale: the agent-MCP increment shipped
with no plan row, and plans 005/006 still describe the Linux gate as blocked
even though the index marks plan 004 DONE. An agent (or operator) cannot use
what it cannot discover; this plan makes the docs match reality.

## Current state

All paths relative to `Sources/RepoPromptHeadlessServer/` unless noted.
Line numbers at commit `0bd2270`.

- `README.md:203-213` — Tools section lists exactly 9 entries ending:

  ```markdown
  - `prompt`
  - `oracle_send` (stdio only)
  - `context_builder` (stdio only)
  ```

  No `agent_run`/`agent_manage`, though both are registered
  (`HeadlessToolSchemas.swift:103-130`) and served in full stdio mode.

- `README.md:78-80`: "it exposes all tools, including `oracle_send` and
  `context_builder`." — same omission; also `README.md:66-70` and
  `README.md:99-103` describe socket exposure pre-007.

- `README.md:137-181` — context builder section; env vars documented at
  156-163; agents.json placeholders at 150-154; `pi` marked UNVERIFIED at
  ~181.

- Env vars READ by code but undocumented in README and absent from
  `Examples/rpce-headless.env`:
  - `RPCE_AGENT_CONFIG` (`HeadlessAgentTypes.swift:11`)
  - `RPCE_AGENT_RUN_DEFAULT_AGENT` — default `"claude"` (`HeadlessAgentTypes.swift:12`)
  - `RPCE_AGENT_SOCKET_DIRECTORY` (`HeadlessAgentTypes.swift:13`)
  - `RPCE_AGENT_OUTPUT_CAPTURE_LIMIT_BYTES` — default 1,000,000 (`HeadlessAgentTypes.swift:14`)
  - plus (post-007) `RPCE_SOCKET_AUTH_TOKEN`.

- `Examples/rpce-headless.env` (16 lines) — only the three oracle vars +
  two XDG paths. Note for the docs text: `OracleService` appends
  `rpce-headless` to `XDG_STATE_HOME`, so state lands at
  `/var/lib/rpce-headless/state/rpce-headless` (`OracleService.swift:109-110`).

- `Examples/agents.json:8-11` — the `claude` template includes
  `--permission-mode bypassPermissions`; no warning anywhere.

- `docs/plans/fable/README.md:17-24` — status table rows 001-006 only; the
  agent_run/agent_manage MCP increment (shipped 2026-06-12, validated by
  `HeadlessAgentToolSchemaTests` + `mcp_agent_smoke.py`) has no row.
  (Rows 007-012 were added by the advisor on 2026-06-12 — leave those.)

- `docs/plans/fable/005-headless-oracle-openrouter.md:252-253` — stale gate:

  ```markdown
  - [ ] If plan 004 DONE: mock test prints `ORACLE OK` in the Linux container
    — skipped; blocked by plan 004 / Docker plan-001 gate
  ```

  but the index (`docs/plans/fable/README.md:22`) marks 004 DONE.

- `docs/plans/fable/006-headless-context-builder.md:20` — stale: "Linux
  execution remains blocked by plan 004, which inherits the plan-001 Docker
  daemon blocker."

- Known naming divergence to document (from plan 009's review): MCP
  `context_builder` uses `response_type: "clarify"` where the CLI uses
  `--response-type selection` (`HeadlessContextBuilderService.swift:199-207`
  vs `main.swift:150-154`); CLI defaults (`--agent fake`, budget 118,500)
  differ from MCP defaults (env-driven `claude`, 160k/120k); `review` (like
  `question`/`plan`) invokes the oracle.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Markdown sanity | `grep -n "agent_run" Sources/RepoPromptHeadlessServer/README.md` | ≥3 matches after edits |
| Env example sanity | `grep -c "RPCE_" Sources/RepoPromptHeadlessServer/Examples/rpce-headless.env` | ≥12 after edits |
| No code touched | `git diff --stat -- Sources/RepoPromptHeadlessServer/*.swift` | empty |

## Scope

**In scope**:
- `Sources/RepoPromptHeadlessServer/README.md`
- `Sources/RepoPromptHeadlessServer/Examples/rpce-headless.env`
- `Sources/RepoPromptHeadlessServer/Examples/agents.json` (comment-equivalent: JSON has no comments — see Step 4)
- `docs/plans/fable/README.md`
- `docs/plans/fable/005-headless-oracle-openrouter.md` (two lines)
- `docs/plans/fable/006-headless-context-builder.md` (one passage)

**Out of scope**:
- Any `.swift` or `.py` file. If docs and code disagree, STOP and report —
  do not "fix" code from a docs plan.
- Root `README.md` / root `CLAUDE.md` (no headless content there today).
- `Examples/rpce-headless.service` beyond what plan 007 already added.

## Git workflow

- Branch: `codex/fable-headless-linux` (or child `fable/012-docs-hygiene`).
- Preflight before each commit: `.agents/skills/rpce-contribution-check/scripts/preflight.sh commit`
- No push without operator instruction.

## Steps

### Step 1: README — agent tools section + Tools list

- Add to the Tools list (after `prompt`):
  `- `agent_run` (stdio / authenticated full-tool socket)` and
  `- `agent_manage` (stdio / authenticated full-tool socket)` — wording per
  007's landed reality.
- New section `## Headless agent runner` (place after
  `## Headless context builder`): document ops
  (`agent_run`: start/poll/wait/cancel; `agent_manage`: list_agents/
  list_sessions/get_log/stop_session/cleanup_sessions), that sessions are
  process-backed (NOT app Agent Mode; no steer/respond/worktrees), that the
  same `agents.json` template format drives both `agent_run` and the
  context builder, and the four env vars with defaults:
  `RPCE_AGENT_CONFIG` (default `~/.config/rpce-headless/agents.json`),
  `RPCE_AGENT_RUN_DEFAULT_AGENT` (default `claude`),
  `RPCE_AGENT_SOCKET_DIRECTORY`, `RPCE_AGENT_OUTPUT_CAPTURE_LIMIT_BYTES`
  (default 1000000). Mention `cleanup_sessions` is the caller's job for
  reclaiming temp dirs (until auto-expiry lands; see plan 008 notes).
- Update the stdio prose (`README.md:78-80`, `:99-103`, `:66-70`) to (a)
  include the agent tools in "all tools", (b) describe the post-007 split:
  default sockets = discovery-restricted; `--expose-all-tools` socket =
  full toolset behind `RPCE_SOCKET_AUTH_TOKEN` handshake (document the
  one-line `{"rpce_auth":{"token":...}}` preamble and `connect --auth`).

**Verify**: `grep -n "agent_run\|agent_manage\|RPCE_AGENT_" Sources/RepoPromptHeadlessServer/README.md` shows the list entries, the new section, and all four env vars.

### Step 2: README — security posture

New short section `## Security notes` (before `## v1 semantics`):
- No MCP-level auth on stdio; socket auth exists only via 007's
  `--expose-all-tools` + token. **Never** expose the socket or a stdio
  bridge over TCP without adding real authentication and TLS.
- Anything running as the service user can connect to the socket;
  single-tenant hosts only.
- The example `claude` agent template uses
  `--permission-mode bypassPermissions`: a spawned agent can take arbitrary
  host actions as the service user. Call it out as a deliberate convenience
  default to review before VPS deployment (alternatives: remove the flag,
  sandbox the service user, restrict the unit further).
- Token rotation: edit EnvironmentFile, `systemctl restart rpce-headless`.

**Verify**: `grep -n "bypassPermissions" Sources/RepoPromptHeadlessServer/README.md` → ≥1 match.

### Step 3: README — divergences that confuse agents

In the context-builder section, add a compact "CLI vs MCP" note: CLI
`--response-type selection` ≙ MCP `response_type: "clarify"`; CLI defaults
(`--agent fake`, token budget 118,500) are dev-oriented while MCP defaults
are env-driven (`claude`, 160k clarify / 120k otherwise); `question`,
`plan`, **and `review`** invoke the oracle (post-009: only after a
successful, non-empty discovery).

**Verify**: `grep -n "clarify" Sources/RepoPromptHeadlessServer/README.md` → ≥2 matches.

### Step 4: Seed the example env file

Append to `Examples/rpce-headless.env`, all commented-out with one-line
explanations, grouped under two new comment headers:
`# --- Agent runner (agent_run/agent_manage) ---`:
`RPCE_AGENT_CONFIG`, `RPCE_AGENT_RUN_DEFAULT_AGENT`,
`RPCE_AGENT_SOCKET_DIRECTORY`, `RPCE_AGENT_OUTPUT_CAPTURE_LIMIT_BYTES`;
`# --- Context builder ---`: the five `RPCE_CONTEXT_BUILDER_*` vars.
(`RPCE_SOCKET_AUTH_TOKEN` was added by plan 007 — keep, don't duplicate.)
Also add one comment line noting oracle state lands under
`$XDG_STATE_HOME/rpce-headless`.

For `agents.json` (JSON, no comments): do not modify the file; the
bypassPermissions warning lives in the README (Step 2) — confirm the README
references `Examples/agents.json` by name next to the warning.

**Verify**: `grep -c "RPCE_" Sources/RepoPromptHeadlessServer/Examples/rpce-headless.env` ≥ 12.

### Step 5: Plan-index hygiene

- `docs/plans/fable/README.md`: under the status table, add a short
  `## Shipped outside plans` subsection:
  "2026-06-12 — headless `agent_run`/`agent_manage` MCP tools
  (process-backed subset: start/poll/wait/cancel;
  list_agents/list_sessions/get_log/stop_session/cleanup_sessions) shipped
  without a plan row; validated by `HeadlessAgentToolSchemaTests` and
  `mcp_agent_smoke.py`. Hardening tracked in plans 008/010/011."
- `005-headless-oracle-openrouter.md:252-253`: rewrite the unchecked item to
  "- [ ] Mock test prints `ORACLE OK` in the Linux container — unblocked by
  plan 004 (DONE) since 2026-06-12; container run still pending."
- `006-headless-context-builder.md:20`: replace the "remains blocked by plan
  004" sentence with "Linux gate opened when plan 004 completed; Linux
  container validation of the context builder is still pending."

**Verify**: `grep -n "Shipped outside plans" docs/plans/fable/README.md` → 1 match; `grep -rn "blocked by plan 004" docs/plans/fable/006-headless-context-builder.md` → no matches.

## Test plan

Docs-only: the verification greps above, plus one human-level pass — read
the final README top to bottom and confirm a fresh agent could (1) discover
both agent tools exist, (2) configure `agents.json` + env for a first
`agent_run start`, (3) understand which transport exposes which tools.

## Done criteria

- [ ] All Step verifications pass
- [ ] `git diff --stat` touches only the six in-scope files
- [ ] README documents: both agent tools, all 4 + 5 + 1 env vars, the 007 transport split, the bypassPermissions warning, the clarify/selection divergence
- [ ] `docs/plans/fable/README.md` status row for 012 updated (and 005/006 stale text fixed)

## STOP conditions

Stop and report back (do not improvise) if:

- Plan 007 is not DONE (the transport section would document fiction).
- Code contradicts this plan's claims (e.g. an env var was renamed): report
  the mismatch; docs follow code, but the discrepancy list must go to the
  reviewer.
- README headings have drifted so far that the placement instructions are
  ambiguous — propose a placement in your report instead of guessing.

## Maintenance notes

- Every future headless tool addition must touch: README Tools list, the
  relevant env-var section, `rpce-headless.env`, and (if socket-relevant)
  the security notes — consider this plan's structure the checklist.
- The `docs/plans/fable/README.md` "Shipped outside plans" section is the
  pressure valve for fast-moving work; prefer a real plan row when the work
  is bigger than a day.
