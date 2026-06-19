---
title: "feat: Headless Parity Contract (Capability Map + Drift-Prevention Hook)"
type: feat
status: active
date: 2026-06-18
origin: docs/investigations/feature-parity/app-vs-headless-parity-design.md
---

# feat: Headless Parity Contract (Capability Map + Drift-Prevention Hook)

## Summary

Establish a living app↔headless capability/parity map seeded from the design doc's gap matrix, plus a drift-prevention hook wired into the existing `rpce-contribution-check` preflight so any future app tool addition requires a recorded headless parity decision. This is the cross-cutting contract that Lanes 1–5 close rows against, and it is the single highest-leverage defense against the silent drift that necessitated the entire parity effort.

---

## Problem Frame

The design doc is a point-in-time snapshot of parity that already silently rotted: the headless self-doc surface (`headless_status`/`headless_capabilities`) truthfully reports what headless has, but nothing records what the app gained that headless did not. Every app tool addition silently widens the gap. The `CustomWorkflowExtensibility` shape in `HeadlessCapabilities` is the seed of a deferred-port contract — but for one capability only, with no app-side mirror, no per-row parity decision, and no drift-prevention hook. Lane 0 generalizes that shape to every capability row and makes the contract enforced, not advisory.

---

## Requirements

- R1. A tracked parity map artifact seeded from the design doc's consolidated gap matrix, with one row per capability carrying: a stable `capability_id`, the app tool constant(s), the headless tool/status, an explicit `parity_decision` (`ported`/`deferred`/`wontfix`/`partial`), an owning lane, and a mandatory rationale for non-`ported` decisions.
- R2. The map must be exhaustive against the authoritative app tool-name surfaces (`MCPWindowToolGroup.orderedToolNames` ∪ `MCPGlobalToolName.orderedToolNames`) and the headless tool surface (`HeadlessToolSchemas.tools`).
- R3. A drift-prevention hook in the `rpce-contribution-check` preflight that fails push mode when an app tool-name enum file (`MCPWindowToolNames.swift` / `MCPWindowToolGroup.swift` / `MCPGlobalToolNames.swift`) changes without a corresponding map row carrying a valid `parity_decision` (and non-empty rationale for non-`ported`).
- R4. The `parity_decision` vocabulary aligns with the repo's triage-label vocab (`docs/agents/triage-labels.md`): `wontfix` is the identical string; `deferred` maps to lane routing; undecided rows fail the check (forcing a real decision, mirroring how `needs-info` blocks).

---

## Scope Boundaries

- The map + hook are the spine. Runtime parity projection into `headless_capabilities` (a `ParitySummary` field populated from the map) is an **optional** unit, not required for Lane 0 to deliver value.
- The hook keys off the three authoritative app tool-name source files only. Tools added outside those files are a source-layout/guardrails concern, not Lane 0's.
- The hook does **not** block headless-side changes (`HeadlessToolSchemas.swift`, `HeadlessAgentSessionManager.swift`) — those are the port itself. A headless→map one-way exhaustiveness check is `warn`-only so a port lane is not double-gated mid-work.
- Lane 0 does not port any capability. It is the contract; Lanes 1–5 close rows.

### Deferred to Follow-Up Work
- Runtime parity projection into `headless_capabilities` (`ParitySummary` field, generated JSON sidecar) — optional unit U3; defer unless a lane needs the live contract at runtime.
- Per-op parity granularity (e.g. `agent_run.steer_respond` as a sub-row of `agent_run`) — a seeding decision in U1, not a structural commitment.

---

## Context & Research

### Relevant Code and Patterns
- `Sources/RepoPromptHeadlessServer/HeadlessCapabilities.swift` — `HeadlessCapabilitiesReply`, `HeadlessStatusReply`, `NativeWorkflowGuide.CustomWorkflowExtensibility` (the existing deferred-port contract shape for one capability), `contractVersion`.
- `Sources/RepoPromptHeadlessServer/HeadlessToolSchemas.swift` — `HeadlessToolSchemas.tools` (headless side of the map), `discoveryToolNames` (transport-aware exposure).
- `Sources/RepoPrompt/Infrastructure/MCP/WindowTools/MCPWindowToolGroup.swift`, `MCPWindowToolNames.swift`, `MCPGlobalToolNames.swift` — the authoritative app tool-name surfaces (the app side of the map; the drift-gate trigger files).
- `.agents/skills/rpce-contribution-check/scripts/preflight.sh` — the existing push-mode preflight with boundary-dispatched `range_contains` blocks; the insertion point for the parity check.
- `.agents/skills/rpce-contribution-check/references/validation-matrix.md` — the per-boundary "Minimum focused evidence" table; the parity rule gets a row here.
- `docs/agents/triage-labels.md` — canonical triage vocab (`needs-triage`/`needs-info`/`ready-for-agent`/`ready-for-human`/`wontfix`); the parity-decision vocab aligns here.

### Institutional Learnings
- The design doc's "silent drift" diagnosis (§1 caveat, §6) is the failure mode this lane exists to prevent. Advisory-only hooks reproduce that failure mode; the hook must be enforcing in push mode.

---

## Key Technical Decisions

- **Markdown map, not generated JSON:** a human-editable table the preflight parses with a tight regex is cheaper, more reviewable, and harder to silently regenerate away than a derived blob. The map is small (≈30 rows) and changes only when an app tool changes. (If format drift becomes a problem, promote to a generated JSON sidecar edited via the map.)
- **`rejected` is a distinct `headless_status` from `absent`:** `agent_run` exists on both surfaces but headless explicitly rejects `steer`/`respond`/`worktree` (`HeadlessAgentSessionManager.swift:545-551`). "Never built" vs "built and gated" changes a lane's work from "port" to "ungate + wire" — the distinction is load-bearing.
- **Enforcing in push mode, advisory in commit mode:** commit mode `warn`-only keeps in-flight staging unblocked; the gate fires at push where the outgoing range is stable. Advisory-only is the exact failure mode the design doc diagnoses.
- **Headless→map check is `warn`-only:** a port lane editing `HeadlessToolSchemas.swift` mid-port must not be blocked by a "headless tool not in map" failure; only the app-side change is enforcing.

---

## Open Questions

### Resolved During Planning
- Map location: `docs/parity/app-headless-capability-map.md` (new `docs/parity/` dir — visible as a contract, not a one-off investigation; the design doc stays as the findings record).
- Hook enforcement level: enforcing in push, advisory in commit.

### Deferred to Implementation
- Exact `capability_id` slug granularity per row (e.g. `agent_run.steer_respond` vs separate rows) — a U1 seeding decision.
- Whether `contractVersion` bumps on a row flip `deferred→ported` — recommend bump only when the headless tool *set* changes, not on every map edit.

---

## Implementation Units

### U1. Seed the parity map

**Goal:** Create the tracked parity contract artifact, seeded exhaustively from the design doc gap matrix.

**Requirements:** R1, R2

**Dependencies:** None

**Files:**
- Create: `docs/parity/app-headless-capability-map.md`

**Approach:**
- Seed every row from the design doc "Consolidated gap matrix" (legend ✅/🟡/❌/🔴 → `present`/`partial`/`absent`/`absent+load-bearing`; 🔴 rows additionally carry `decision_rationale` citing the dependency-spine section).
- Seed shared rows (file/tree/search/structure/read, selection get/add/remove/set/clear, `workspace_context`/`prompt` basic) as `ported` (shared via ContextCore).
- Seed headless-only rows (`headless_status`, `headless_capabilities`) as `wontfix`-by-design with rationale "headless-only self-doc; app exposes docs differently, no parity target."
- Set `owning_lane` on absent rows per the lane index assignment (Layer 1 → Lane 1; Layer 2 → Lane 2; Layer 3 leaves → Lanes 3/4/5).
- Confirm exhaustiveness: every name in `MCPWindowToolGroup.orderedToolNames` ∪ `MCPGlobalToolName.orderedToolNames` ∪ `HeadlessToolSchemas.tools` has a row.

**Patterns to follow:**
- The `CustomWorkflowExtensibility` shape in `HeadlessCapabilities.swift` (the existing one-capability deferred-port contract).

**Test scenarios:**
- Happy path: map's `app_tool` column equals `MCPWindowToolGroup.orderedToolNames` ∪ `MCPGlobalToolName.orderedToolNames` (no app tool missing, no map row references a non-existent app tool).
- Happy path: map's `headless_tool` column is a subset of `HeadlessToolSchemas.tools` names; every `HeadlessToolSchemas.tools` name has a row (headless-only with `app_tool: —`).
- Edge case: every matrix row in the design doc has a corresponding map row; 🔴 rows carry `decision_rationale`.

**Verification:**
- The map file exists at `docs/parity/app-headless-capability-map.md` and is exhaustive against both tool-name surfaces by inspection.

---

### U2. Wire the drift-prevention hook into the preflight

**Goal:** Make app tool-name additions require a recorded parity decision, enforced at push.

**Requirements:** R3, R4

**Dependencies:** U1

**Files:**
- Modify: `.agents/skills/rpce-contribution-check/scripts/preflight.sh`
- Modify: `.agents/skills/rpce-contribution-check/references/validation-matrix.md`

**Approach:**
- Add a push-mode boundary block (after `resolve_outgoing_base`, alongside existing `range_contains` blocks), triggered when the outgoing range touches any of `MCPWindowToolNames.swift`, `MCPWindowToolGroup.swift`, `MCPGlobalToolNames.swift`.
- Two sub-checks (cheap, no Swift build):
  1. *Exhaustiveness:* parse the three enum files for `static let <id> = "<toolName>"` lines (line-grep, matching the script's existing text-grep style — NOT a Swift AST parse; the enum files are trivial constant declarations); assert every `<toolName>` appears in the map's `app_tool` column.
  2. *Decision present:* for any newly-added app tool name not in the prior range's map, assert the map now has a row whose `parity_decision` is in `{ported, deferred, wontfix, partial}` and whose `decision_rationale` is non-empty when the decision is not `ported`.
- Reject `tbd`/`later`/`blocked` (forces a real decision, aligning with how `needs-info` blocks).
- Enforcing (non-zero exit) in push mode; `warn` only in commit mode.
- Add a row to `validation-matrix.md` so contributors see the rule alongside build/test rules.
- Failure message names the new/changed tool constant, points at the map path, and lists the required `parity_decision` values.

**Patterns to follow:**
- The existing `range_contains` boundary blocks and `fail()`/`warn()` helpers in `preflight.sh`.

**Test scenarios:**
- Error path: PR adds `static let newTool = "new_tool"` to `MCPWindowToolNames.swift` with no map change → `preflight.sh push` exits non-zero; message names `new_tool` and points at the map.
- Error path: PR adds the tool *and* a map row with `parity_decision: deferred`, empty rationale → exits non-zero; requires non-empty rationale.
- Happy path: PR adds the tool *and* a map row with `parity_decision: wontfix` + rationale "out of scope for headless; single-window design" → passes.
- Happy path: PR renames a tool constant value and updates the map's `app_tool` cell → passes (renames allowed when tracked).
- Edge case: PR changes only `HeadlessToolSchemas.swift` (a port) and flips a map row to `ported` → passes (headless→map check is `warn`-only).

**Verification:**
- A synthetic app tool-name addition without a map row fails push preflight; with a valid map row it passes.

---

### U3. (Optional) Project parity into `headless_capabilities`

**Goal:** Let an agent discover the current parity closure state at runtime without reading the doc.

**Requirements:** R1 (the map is the source)

**Dependencies:** U1

**Files:**
- Modify: `Sources/RepoPromptHeadlessServer/HeadlessCapabilities.swift`

**Approach:**
- Add an optional `parity: ParitySummary?` to `HeadlessCapabilitiesReply` (mirrors the map: rows + roll-up counts `ported`/`deferred`/`wontfix`/`partial`/`unknown`).
- Populate from the **same markdown map** (parse at boot, or from a generated JSON sidecar kept in sync by the preflight). Do **not** hand-maintain a second copy in Swift — that recreates the drift problem inside the fix.
- Add a parity roll-up to `HeadlessStatusReply` (counts only) for the compact triage path.

**Patterns to follow:**
- `CustomWorkflowExtensibility` precedent (a deferred-port contract already projected into the self-doc payload).

**Test scenarios:**
- Happy path: `rpce-headless capabilities --json | jq '.parity'` returns rows + roll-up counts matching the map; `unknown == 0`.

**Test expectation: none -- optional unit; defer unless a lane needs the live contract at runtime.**

**Verification:**
- If shipped: `headless_capabilities` reports parity status consistent with the map.

---

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| Map rot if the hook is advisory-only (the precise failure mode the design doc diagnoses) | Ship U2 enforcing in push mode (non-zero exit blocks push), not advisory. Commit-mode `warn` only is acceptable. |
| False positives in the preflight grep (double-counting case-arm references in `MCPWindowToolGroup.swift`) | Key the exhaustiveness check off the string literals in `MCPWindowToolNames.swift`/`MCPGlobalToolNames.swift` (the `= "tool_name"` lines), not the case-arm references in `MCPWindowToolGroup.swift`. Document this scope in the validation-matrix row. |
| Maintenance burden of a second copy if U3 hand-maintains a Swift parity struct | U3 must parse the markdown map (or a generated JSON sidecar kept in sync by the preflight), never a hand-typed Swift mirror. If parsing is too costly, defer U3. |
| Decision vocabulary creep (contributors invent `tbd`/`later`/`blocked`) | Preflight asserts the value is in the controlled set; `tbd` is explicitly rejected. |

---

## Sources & References

- **Origin document:** [docs/investigations/feature-parity/app-vs-headless-parity-design.md](docs/investigations/feature-parity/app-vs-headless-parity-design.md) (§1 Overview, §6 Consolidated gap matrix)
- Related code: `Sources/RepoPromptHeadlessServer/HeadlessCapabilities.swift`, `HeadlessToolSchemas.swift`; `Sources/RepoPrompt/Infrastructure/MCP/WindowTools/MCPWindowToolGroup.swift`, `MCPWindowToolNames.swift`, `MCPGlobalToolNames.swift`
- Related skill: `.agents/skills/rpce-contribution-check/` (preflight + validation matrix)
- Lane index: [2026-06-18-001-feat-app-headless-parity-lane-index-plan.md](2026-06-18-001-feat-app-headless-parity-lane-index-plan.md)
