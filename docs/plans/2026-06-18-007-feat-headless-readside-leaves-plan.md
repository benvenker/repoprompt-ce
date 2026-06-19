---
title: "feat: Headless Read-side Parity Leaves (Selection Slices, Prompt Presets/Export, Oracle Family, agent_explore)"
type: feat
status: active
date: 2026-06-18
origin: docs/investigations/feature-parity/app-vs-headless-parity-design.md
---

# feat: Headless Read-side Parity Leaves (Selection Slices, Prompt Presets/Export, Oracle Family, agent_explore)

## Summary

Close four read-side parity gaps in `rpce-headless`: `manage_selection` slices/preview/promote/demote, `prompt` presets/export, oracle family completion (`oracle_chat_log`/`oracle_utils`/`oracle_send` enhancements), and a constrained `agent_explore` stopgap. The first three leaves are independent of Lanes 1–4 and can proceed immediately; `agent_explore` is the exception — its full port overlaps the runtime substrate, so this plan ships a read-only one-shot probe stopgap and defers the full port.

---

## Problem Frame

Headless has partial read-side parity today. `manage_selection` supports `get`/`add`/`remove`/`set`/`clear` but throws on `slices`/`preview`/`promote`/`demote` (`HeadlessWorkspaceHost.swift:192-215`). `prompt` supports `get`/`set`/`append`/`clear` but throws on `export`/`list_presets`/`select_preset` (`HeadlessWorkspaceHost.swift:234`). The oracle surface has only `oracle_send` — no `oracle_chat_log`, no `oracle_utils`, no `mode`/`new_chat`/`export_response` enhancements. `agent_explore` is entirely absent. These are 🟡/❌ rows in the design doc gap matrix (§1, §6). The shared-core vs app-only inventory is the decisive finding: most of the selection engine and all of the prompt rendering machinery are already linked via `RepoPromptContextCore`; the oracle has a self-contained headless-local service to extend; only `agent_explore` is genuinely substrate-coupled.

---

## Requirements

- R1. `manage_selection` gains `slices` (add/remove/set with line-range inputs), `preview` (non-mutating dry-run), `promote` (codemap→full), and `demote` (full→codemap) — wiring the already-linked `WorkspaceSelectionMutationService` engine (ContextCore), plus a headless-local slice input parser.
- R2. `prompt` gains `export` (render context → write file), `list_presets` (headless-local copy-preset model), and `select_preset` (set active preset on the host). Export reuses the already-linked ContextCore rendering path; presets are a headless-local flag-bundle model, not a port of the app's SwiftUI settings registry.
- R3. Oracle family completion: `oracle_chat_log` (read over existing persisted `OracleChatSession` JSON), `oracle_utils` (`models` + `sessions`), and `oracle_send` enhancements (`mode`/`new_chat`/`export_response`). Extend the headless `OracleService`; do NOT port the app's `OracleViewModel`.
- R4. `agent_explore` ships as a constrained read-only one-shot probe stopgap (batch fresh-session spawn with a read-only permission flag, `poll`/`wait`/`cancel` over process exit). The full port (parent-child ownership, worktree inheritance, needs-input wait) is deferred to after Lanes 1–2 land the runtime substrate.

---

## Scope Boundaries

- Porting the app's `CopyPreset`/`ChatPresetManager`/`ModelPreset` SwiftUI settings registry — headless uses a headless-local preset model instead.
- Porting the app's `OracleViewModel`/`ChatSession`/`AIModel` graph — headless extends its own `OracleService`.
- `ask_oracle` as a separate headless tool — `oracle_send` covers the use case; reserving the name for a post-Lane-1 port avoids a false-parity trap.
- Full `agent_explore` port — parent-child ownership, worktree inheritance, needs-input wait all ride the runtime substrate (Lane 1); deferred.

### Deferred to Follow-Up Work

- **Full `agent_explore` port** — after Lanes 1–2 land the runtime substrate (permission profiles, live parent sessions, waiting-states). The stopgap (U4) ships now with explicit limitations documented.
- **`ask_oracle` headless analogue** — after Lane 1 restores agent-mode ownership semantics; `oracle_send` covers the functional use case until then.
- **`oracle_utils models` catalog beyond the configured default** — optional `RPCE_ORACLE_MODELS` env CSV for a richer model list; v1 returns the default model only.
- **Sharing `CopyPreset` / `parseManageSelectionInputs` back into ContextCore** — recommendation is NOT to share (keep headless-local), but if the app later wants shared preset/parser code, the models would need to move.
- **`prompt select_preset` tab-binding semantics** — the app restricts to explicitly-bound tabs; headless is single-workspace with no tabs, so the restriction is dropped (documented simplification).

---

## Context & Research

### Relevant Code and Patterns

- **Shared selection engine (already linked by headless):** `WorkspaceSelectionMutationService` (`Sources/RepoPromptContextCore/WorkspaceContext/Selection/WorkspaceSelectionMutationService.swift`) — `promotePaths`, `demotePaths`, `mutateSlices`, `buildManageSelectionSet`, `buildSelection` are all public. `StoredSelection` (`Sources/RepoPromptContextCore/WorkspaceContext/Selection/StoredSelection.swift`) is public. Headless already instantiates the service and calls `buildManageSelectionSet`/`addPaths`/`removePaths` in `HeadlessWorkspaceHost.manageSelection`.
- **App-only slice input parser (port target):** `parseManageSelectionInputs` lives in the app's `MCPWindowToolDependencies` (not ContextCore). Handles `#L`-range path syntax, structured `slices` array, and `lines` shorthand. This is the one genuine app-only piece for leaf (a).
- **Shared prompt rendering (already linked):** `PromptContextPreAssemblyService`, `PromptPackagingService.generateClipboardContent`, `PromptContextAccountingService`, `PromptContextResolved` — all in ContextCore, already used by `HeadlessWorkspaceHost.workspaceContext` (lines 253–300). Export is a thin wrapper: render → write file.
- **App-only preset registry (NOT ported):** `CopyPreset`, `CopyPresetKind`, `ChatPreset`, `ChatPresetManager`, `ModelPreset`, `ModelPresetsManager`, `PromptViewModel.resolvePromptContext`/`buildClipboard` — all app-only, SwiftUI-settings-backed.
- **Headless-local oracle (extend, not port):** `OracleService` (actor), `OracleChatSession` (persisted JSON under `chats/`), `OracleConfig`/`OpenAICompatibleClient`/`ChatMessage` — all in `Sources/RepoPromptHeadlessServer/`, self-contained. The app's `OracleViewModel` drags in `PromptViewModel`/`WindowManager`/`GlobalSettingsStore` — do NOT port.
- **Oracle env-var config (already present, per AGENTS.md):** `RPCE_ORACLE_API_KEY` (or `OPENROUTER_API_KEY`), `RPCE_ORACLE_BASE_URL` (default OpenRouter), `RPCE_ORACLE_MODEL` (default `openrouter/auto`).
- **Headless current-state rejections:** `HeadlessWorkspaceHost.swift:192-193` (slices), `:214-215` (preview/promote/demote), `:234` (export/list_presets/select_preset). `HeadlessToolSchemas.swift` already *accepts* these enum values in schemas but the host throws — schema descriptions say "Unsupported in headless v1."
- **App agent_explore reference:** `AgentExploreMCPToolService` over `AgentModeViewModel`/`NativeAgentRuntimeControlling` with worktree inheritance + read-only role gating — entirely substrate-coupled.

### Institutional Learnings

- The shared-core vs app-only inventory (breakdown §5) is the key sequencing insight: leaves (a) and (b) are thin wrappers over already-linked ContextCore engines; leaf (c) is a self-contained extension of a headless-local service; leaf (d) is Layer-1 work in disguise.

### External References

- Oracle env-var config documented in `AGENTS.md` (headless oracle section).

---

## Key Technical Decisions

- **Selection leaves are thin wrappers over an already-linked engine:** the real work is wiring 4 ops + a slice input parser + a preview reply shape, not porting mutation logic. The engine invariants (`codemapAutoEnabled` flips, `set` with `mode=slices` preserves unrelated files, codemap_only+slices mutual exclusion) come for free from `WorkspaceSelectionMutationService`.
- **Prompt export v1 is preset-less:** reuse the existing `workspaceContext` rendering path → write file. Delivers the most-requested sub-feature (hand off context to an external AI) with zero new model code. Presets layer on top in a second sub-step.
- **Headless-local `CopyPreset` model, not a port:** a small set of built-in rendering-flag bundles (`Chat`/`Plan`/`Review`/`Files-only`) resolved into `PromptContextResolved` directly. Documented as rendering-only (no model/chat-preset binding, unlike the app's `CopyPreset`).
- **Extend headless `OracleService`, do NOT port app `OracleViewModel`:** the headless oracle is a clean, self-contained OpenAI-compatible client. Porting the app's `OracleViewModel` would drag in `PromptViewModel`, `WindowManager`, and `GlobalSettingsStore`.
- **`oracle_chat_log` is a near-trivial read over existing persisted state:** `OracleService` already persists `OracleChatSession` JSON; the tool just reads it back with `limit`/`include_user` filtering.
- **`agent_explore` v1 = constrained read-only stopgap:** spawn a read-only `claude`/agent process per message (batch → N processes) with a read-only permission flag or `--allowedTools` denylist. NO parent-child ownership, NO worktree inheritance, NO needs-input wait. Clearly documented as a stopgap, not app parity. Full port deferred to post-Lanes-1–2.
- **Shared export file-write helper:** U2 (prompt export) and U3 (oracle `export_response`) both need a root-scoped, traversal-safe file-write helper — build once, share.

---

## High-Level Technical Design

> *This illustrates the intended approach and is directional guidance for review, not implementation specification. The implementing agent should treat it as context, not code to reproduce.*

| Leaf | Shared (ContextCore, already linked) | App-only (port/reimagine) | Headless-local (extend/create) | Substrate-dependent? |
|------|--------------------------------------|---------------------------|--------------------------------|---------------------|
| (a) Selection slices/preview/promote/demote | `WorkspaceSelectionMutationService` engine, `StoredSelection` | `parseManageSelectionInputs` (slice parser) | `HeadlessSelectionInputs.swift` (parser), op wiring | No |
| (b) Prompt presets/export | `PromptPackagingService`, `PromptContextPreAssemblyService`, `PromptContextResolved` | `CopyPreset`/`ChatPresetManager`/`ModelPreset` (NOT ported) | `HeadlessCopyPresets.swift` (preset model), export file-write | No |
| (c) Oracle family | — | `OracleViewModel`/`ChatSession`/`AIModel` (NOT ported) | `OracleService` (extend), `OracleChatLogTool`, `OracleUtilsTool` | No |
| (d) agent_explore | — | `AgentExploreMCPToolService` (substrate-coupled) | `HeadlessAgentSessionManager.executeAgentExplore` (stopgap) | **Yes** (full port); stopgap is independent |

---

## Implementation Units

### U1. Selection slices/preview/promote/demote

**Goal:** Wire the four missing `manage_selection` ops over the already-linked `WorkspaceSelectionMutationService` engine, plus a headless-local slice input parser.

**Requirements:** R1

**Dependencies:** None (independent of Lanes 1–4)

**Files:**
- Create: `Sources/RepoPromptHeadlessServer/HeadlessSelectionInputs.swift` (slice input parser — `#L` syntax, structured `slices` array, `lines` shorthand → `WorkspaceSelectionSliceInput`)
- Modify: `Sources/RepoPromptHeadlessServer/HeadlessWorkspaceHost.swift` (remove `slices` rejection at line 192-193; add `preview`/`promote`/`demote` arms; wire slice `add`/`remove`/`set` via `mutateSlices`)
- Modify: `Sources/RepoPromptHeadlessServer/HeadlessTypes.swift` (optionally add `HeadlessSelectionPreviewReply` if the preview shape differs)
- Modify: `Sources/RepoPromptHeadlessServer/HeadlessToolSchemas.swift` (update schema descriptions — remove "Unsupported in headless v1" for these ops)
- Test: `Tests/RepoPromptHeadlessServerTests/HeadlessSelectionSlicesTests.swift`

**Approach:**
- Sub-step 1 (parser): Port/reimplement `parseManageSelectionInputs` as `HeadlessSelectionInputs.swift`. Parse the `slices` array (`{path, ranges:[{start_line,end_line,description}], lines:"10-20,40"}`) and `#L`-range path syntax into `WorkspaceSelectionSliceInput` (ContextCore type). Co-locate `sliceParseErrors` + `hadExplicitSliceSpec` flags.
- Sub-step 2 (promote/demote): Add `case "promote"`/`case "demote"` arms calling `mutationService.promotePaths`/`demotePaths`. Reject slices in both. Honor `strict` (throw if not mutated). Populate `HeadlessSelectionReply` with the resulting `StoredSelection`.
- Sub-step 3 (slice add/remove/set): Remove the blanket `slices` rejection; for `add`/`remove`, call `mutationService.mutateSlices(...)` with the parsed `WorkspaceSelectionSliceInput` when slices are present; for `set` with `mode=slices`, do file-scoped slice replacement preserving unrelated full files. Keep the `mode=codemap_only` + slices mutual-exclusion check.
- Sub-step 4 (preview): Add `case "preview"` building the candidate via `mutationService.buildManageSelectionSet` (or `mutateSlices`) WITHOUT mutating `self.selection`, returning a reply with the would-be files/slices/invalid paths. Honor `strict`.

**Patterns to follow:**
- `Sources/RepoPrompt/Infrastructure/MCP/WindowTools/MCPSelectionToolProvider.swift` (`executeManageSelection` op arms — the app reference for arg translation and `strict` handling)
- `Sources/RepoPromptContextCore/WorkspaceContext/Selection/WorkspaceSelectionMutationService.swift` (the shared engine — call the same methods with the same arg shapes)

**Test scenarios:**
- Happy path: `paths:["a.swift#L10-20"]` → one `WorkspaceSelectionSliceInput{path:"a.swift", ranges:[10..20]}`, no errors.
- Happy path: `paths:["a.swift#L5"]` → range `5..5`.
- Happy path: `slices:[{path:"a.swift", ranges:[{start_line:1,end_line:10}], lines:"20-30"}]` → two ranges (1-10, 20-30) merged for that path.
- Happy path: `lines:"10-20,40,45-50"` → three ranges.
- Edge case: `ranges:[{start_line:-1}]` → `sliceParseErrors` populated, `hadExplicitSliceSpec=true`.
- Happy path: selection has `a.swift` in codemapFiles; `op:"promote", paths:["a.swift"]` → `a.swift` in selectedFiles, `codemapAutoEnabled:false`.
- Error path: `op:"promote", paths:["missing.swift"], strict:true` → invalidParams ("...did not match").
- Error path: `op:"promote", paths:["a.swift"], slices:[...]` → invalidParams ("promote does not support slices").
- Happy path: selection has `a.swift` full; `op:"demote", paths:["a.swift"]` → `a.swift` in codemapFiles.
- Edge case: demote a file with no codemap support → `codemapUnavailable` message; selection unchanged for that file.
- Happy path: `op:"add", slices:[{path:"a.swift", ranges:[{start_line:1,end_line:10}]}]` → `slices["a.swift"]` populated, selectedFiles unchanged.
- Happy path: `op:"add", paths:["b.swift"], slices:[{path:"a.swift", ranges:[1..10]}]` → both b.swift full and a.swift slice present.
- Happy path: selection has slices `a.swift:[1..10,20..30]`; `op:"remove", slices:[{path:"a.swift", ranges:[20..30]}]` → `a.swift:[1..10]` remains.
- Happy path: selection has `b.swift` full + `a.swift:[1..10]`; `op:"set", mode:"slices", slices:[{path:"a.swift", ranges:[50..60]}]` → `a.swift:[50..60]`, `b.swift` full preserved.
- Error path: `op:"set", mode:"codemap_only", slices:[...]` → invalidParams.
- Happy path: `op:"preview", paths:["a.swift"]` on empty selection → reply shows a.swift; subsequent `op:"get"` still empty (no persistence).
- Happy path: `op:"preview"` and `op:"set"` with identical inputs produce identical `selectedFiles`/`slices`/`codemapFiles`.
- Error path: `op:"preview", paths:["nonexistent"], strict:true` → invalidParams.
- Integration: run promote/demote/slices/preview through the Docker Swift lane (`swift:6.2.4-noble`, `.build-linux` scratch) against a sample repo with codemaps.

**Verification:**
- All four ops (slices/preview/promote/demote) work end-to-end; preview does not mutate state; promote/demote flip `codemapAutoEnabled` to false; slice add/remove/set preserve unrelated files; codemap_only+slices is rejected.

---

### U2. Prompt presets/export

**Goal:** Add `export` (render context → write file), `list_presets` (headless-local preset model), and `select_preset` (set active preset) to the `prompt` tool.

**Requirements:** R2

**Dependencies:** None (independent of Lanes 1–4). U2's export file-write helper is shared with U3.

**Files:**
- Create: `Sources/RepoPromptHeadlessServer/HeadlessCopyPresets.swift` (headless-local `HeadlessCopyPreset` model + built-ins + resolver)
- Modify: `Sources/RepoPromptHeadlessServer/HeadlessWorkspaceHost.swift` (add `exportPrompt(path:copyPreset:)`, `listPresets()`, `selectPreset(name:)`; add active-preset state var; add `case "export"`/`"list_presets"`/`"select_preset"` arms; add shared `writeExportFile(path:content:)` helper)
- Modify: `Sources/RepoPromptHeadlessServer/HeadlessToolSchemas.swift` (update `prompt` schema descriptions — remove "Unsupported in headless v1")
- Test: `Tests/RepoPromptHeadlessServerTests/HeadlessPromptPresetsExportTests.swift`

**Approach:**
- Sub-step 1 (preset-less export): Reuse the existing `workspaceContext` rendering path (`HeadlessWorkspaceHost.workspaceContext`, lines 253-300) to produce the context string, then write it to `path` via a shared root-scoped, traversal-safe file-write helper. Return `{path, tokens, bytes, files}`. No preset selection yet — use the default `PromptContextResolved`.
- Sub-step 2 (preset model + list_presets): Define `HeadlessCopyPreset` (name + a `PromptContextResolved`-shaped flag bundle: `includeFiles`/`includeUserPrompt`/`includeMetaPrompts`/`includeFileTree`/`fileTreeMode`/`codeMapUsage`/`gitInclusion`). Seed built-ins (`Chat`, `Plan`, `Review`, `Files-only`). `list_presets` returns them. Resolve preset by name/UUID. No user-editable registry in v1.
- Sub-step 3 (export with preset + select_preset): Accept `copy_preset` resolving through the preset model; render via the existing ContextCore preassembly/packaging with the resolved `PromptContextResolved` (replace the hardcoded `cfg` in `workspaceContext` with the resolved preset when a preset is active). `select_preset` sets an in-memory active preset on the host (single-workspace, no tab binding).

**Patterns to follow:**
- `Sources/RepoPrompt/Infrastructure/MCP/WindowTools/MCPPromptContextToolProvider.swift` (`executePrompt` export/preset arms — the app reference for the reply shape `{path, tokens, bytes, files, copyPreset}`)
- `Sources/RepoPromptContextCore/PromptServices/PromptPackagingService.swift` (the shared renderer — already used by `workspaceContext`)

**Test scenarios:**
- Happy path: `op:"export", path:"context.txt"` with a selection → file written under the first loaded root; reply `{path, tokens>0, bytes>0, files:[...]}`.
- Happy path: export with empty selection → file still written (prompt + tree + tokens); tokens for prompt only.
- Error path: `op:"export"` with no path → invalidParams ("path required for export").
- Error path: `op:"export", path:"../../etc/passwd"` → rejected (path escapes roots).
- Happy path: `op:"list_presets"` → returns Chat/Plan/Review/Files-only with expected flag bundles.
- Happy path: resolve `"Plan"` → `PromptContextResolved` with plan-shaped flags.
- Error path: `"Nope"` → invalidParams ("preset not found").
- Happy path: `op:"export", path:"p.txt", copy_preset:"Plan"` → output shaped per Plan (e.g. `includeFileTree=true`); differs from default export.
- Happy path: `op:"select_preset", preset:"Review"` then `workspace_context` → context rendered with Review flags.
- Happy path: select_preset then export (no `copy_preset` arg) → export uses the active Review preset.
- Integration: export file readable and contains expected sections (prompt, file tree, file contents).

**Verification:**
- `export` writes a root-scoped file with token/byte/file counts; `list_presets` returns built-ins; `select_preset` persists an active preset that shapes subsequent `workspace_context`/`export`; path traversal is rejected; presets are rendering-only (no model/chat-preset binding).

---

### U3. Oracle family completion

**Goal:** Add `oracle_chat_log` (read over persisted chats), `oracle_utils` (`models` + `sessions`), and `oracle_send` enhancements (`mode`/`new_chat`/`export_response`) by extending the headless `OracleService`.

**Requirements:** R3

**Dependencies:** None (independent of Lanes 1–4). Shares the export file-write helper from U2.

**Files:**
- Create: `Sources/RepoPromptHeadlessServer/OracleChatLogTool.swift` (thin handler mirroring `OracleSendTool.swift`)
- Create: `Sources/RepoPromptHeadlessServer/OracleUtilsTool.swift` (thin handler for `models`/`sessions`)
- Modify: `Sources/RepoPromptHeadlessServer/OracleService.swift` (add `chatLog(chatID:limit:includeUser:)`, `listSessions()`, `listModels()`, extend `send` with `mode`/`new_chat`/`export_response`)
- Modify: `Sources/RepoPromptHeadlessServer/OracleSendTool.swift` (pass new args through)
- Modify: `Sources/RepoPromptHeadlessServer/HeadlessToolSchemas.swift` (add `oracle_chat_log` + `oracle_utils` tools; update `oracle_send` schema with `mode`/`new_chat`/`export_response`)
- Modify: `Sources/RepoPromptHeadlessServer/HeadlessMCPServer.swift` (dispatch new tools)
- Test: `Tests/RepoPromptHeadlessServerTests/HeadlessOracleFamilyTests.swift`

**Approach:**
- Sub-step 1 (`oracle_chat_log` — cheapest): Add `OracleService.chatLog(chatID:limit:includeUser:)` that loads the persisted `OracleChatSession` JSON (or, if `chatID` nil, picks the most-recently-modified file in `chats/`), maps `ChatMessage(role,content)` → `{role, text}` (skip `system` unless included), applies `limit` (default 8, clamp 1–50) and `include_user` (default false), truncates each message to 8000 chars. Return `{chat_id, messages}`. New `OracleChatLogTool` + schema + dispatch.
- Sub-step 2 (`oracle_utils`): New tool with `op=models|sessions`. `models`: return `RPCE_ORACLE_MODEL` (default `openrouter/auto`) + the `model` override path (optionally read `RPCE_ORACLE_MODELS` env CSV). `sessions`: list JSON files in `chats/` with `{id, message_count, last_modified}`. New `OracleUtilsTool` + schema + dispatch.
- Sub-step 3 (`oracle_send` enhancements): Extend `OracleService.send` to accept `mode` (chat/plan/review) → swap the system prompt (mode-specific variants of the current system prompt). Add `new_chat:true` → force a fresh session (ignore `chat_id`). Add `export_response:true` → after streaming, write the assistant reply to a file via the shared export helper (from U2) and return `oracle_export_path`/`oracle_export_instruction`. Update schema description.

**Patterns to follow:**
- `Sources/RepoPromptHeadlessServer/OracleSendTool.swift` (the existing thin handler pattern — mirror for `OracleChatLogTool` and `OracleUtilsTool`)
- `Sources/RepoPrompt/Features/Chat/ViewModels/Oracle/OracleViewModel+MCP.swift` (`tool_oracleChatLog` — the app reference for the reply shape `{role, text}` + `limit`/`include_user` semantics)

**Test scenarios:**
- Happy path: `oracle_send message:"hi"` → `oracle_chat_log` (no chat_id) → returns the assistant reply; `include_user:false` omits the user "hi"; `limit:1` returns 1 message.
- Happy path: send to chat_id X, then `oracle_chat_log chat_id:X` → returns that chat's tail.
- Error path: `oracle_chat_log chat_id:"nope"` → error ("chat not found").
- Edge case: no chats dir / no sessions → "No chats found".
- Edge case: `limit:0` → clamped to 1; `limit:999` → clamped to 50.
- Edge case: a >8000-char assistant message → truncated with `… [truncated]`.
- Happy path: `oracle_utils op:"models"` → returns `openrouter/auto` (or `RPCE_ORACLE_MODEL`).
- Happy path: after a send, `oracle_utils op:"sessions"` → non-empty list with the chat id + message_count.
- Edge case: fresh state → empty sessions list.
- Happy path: `oracle_send message:"x", mode:"plan"` → system prompt is the plan variant (assert via a mock/recorded client).
- Happy path: `oracle_send chat_id:X, new_chat:true` → returns a NEW chat_id != X.
- Happy path: `oracle_send message:"x", export_response:true` → reply includes `oracle_export_path`; file exists with the assistant text.
- Error path: `mode:"bogus"` → invalidParams.
- Error path: unset `RPCE_ORACLE_API_KEY`/`OPENROUTER_API_KEY` → `oracle_send` errors with the documented "requires RPCE_ORACLE_API_KEY or OPENROUTER_API_KEY" (family tools surface the same error consistently).
- Error path: point `RPCE_ORACLE_BASE_URL` at a 500 endpoint → `oracle_send` surfaces HTTP error; `oracle_chat_log` still reads prior persisted sessions; failed sends don't persist partial session files.
- Integration: run `oracle_chat_log`/`oracle_utils`/enhanced `oracle_send` end-to-end against a mock OpenAI-compatible endpoint (or a recorded fixture) in the Docker Swift lane.

**Verification:**
- `oracle_chat_log` reads persisted chats with correct filtering/truncation; `oracle_utils` lists models + sessions; `oracle_send` supports `mode`/`new_chat`/`export_response`; the auth error path is consistent across the family; failed sends don't persist partial sessions.

---

### U4. agent_explore stopgap (read-only one-shot probe)

**Goal:** Ship a constrained `agent_explore` that spawns a read-only agent process per message (batch → N processes) with `poll`/`wait`/`cancel` over process exit. Explicitly NOT app parity — no parent-child ownership, no worktree inheritance, no needs-input wait.

**Requirements:** R4

**Dependencies:** None for the stopgap (reuses `HeadlessAgentSessionManager` spawn machinery). The **full** port is deferred to after Lanes 1–2 (requires the runtime substrate: permission profiles, live parent sessions, waiting-states).

**Files:**
- Modify: `Sources/RepoPromptHeadlessServer/HeadlessAgentSessionManager.swift` (add `executeAgentExplore` with `start`/`poll`/`wait`/`cancel` ops)
- Modify: `Sources/RepoPromptHeadlessServer/AgentLauncher.swift` (add a read-only agent template — `--permission-mode` read-equivalent or `--allowedTools` denylist excluding edit/git/oracle/worktree tools)
- Modify: `Sources/RepoPromptHeadlessServer/HeadlessToolSchemas.swift` (add `agent_explore` tool schema with `start`/`poll`/`wait`/`cancel` ops, `message`/`messages` args)
- Modify: `Sources/RepoPromptHeadlessServer/HeadlessMCPServer.swift` (dispatch `agent_explore`)
- Test: `Tests/RepoPromptHeadlessServerTests/HeadlessAgentExploreStopgapTests.swift`

**Approach:**
- `start`: spawn a read-only `claude`/agent process per `message` (batch `messages` → N independent processes, one session_id each). Use a read-only permission flag or `--allowedTools` denylist. Return one `session_id` per probe.
- `poll`/`wait`/`cancel`: reuse `HeadlessAgentSessionManager`'s existing spawn/snapshot/terminate machinery. `wait` = wait for process exit (NOT needs-input — headless has no waiting-states).
- Reject `steer`/`respond`/`inherit_worktree`/`worktree_create` with invalidParams (documented stopgap limitations).
- `headless_capabilities` must report `agent_explore` as `stopgap`/`limited` with an explicit list of absent capabilities. Tool description must say "headless read-only probe stopgap; no parent-session ownership, no worktree inheritance, no interactive wait."

**Patterns to follow:**
- `Sources/RepoPromptHeadlessServer/HeadlessAgentSessionManager.swift` (`executeAgentRun` — the existing spawn/snapshot/terminate pattern to reuse for `executeAgentExplore`)
- `Sources/RepoPrompt/Infrastructure/MCP/Agent/AgentExploreMCPToolService.swift` (the app reference for the tool contract shape — `start`/`poll`/`wait`/`cancel`, `message`/`messages` — NOT for the substrate-dependent semantics)

**Test scenarios:**
- Happy path: `op:"start", message:"find the entry point"` → returns `session_id`; `op:"poll", session_id:X` → status running/terminal.
- Happy path: `messages:["a","b","c"]` → 3 session_ids; each independent.
- Happy path: start then `op:"cancel", session_id:X` → terminal status.
- Happy path: start (short prompt) then `op:"wait", session_id:X, timeout:30` → returns completed status + stdout.
- Integration: probe asked to create a file → probe cannot (permission denied); working tree unchanged.
- Error path: `op:"steer"` → invalidParams ("Unsupported... Use start, poll, wait, or cancel").
- Edge case: `inherit_worktree` arg → invalidParams or ignored (documented stopgap limitation).

**Verification:**
- `agent_explore` spawns read-only probes (batch → N sessions); `poll`/`wait`/`cancel` work over process exit; read-only enforcement proven via integration test; `steer`/`respond`/worktree args rejected; `headless_capabilities` reports the tool as `stopgap`/`limited`.

---

## System-Wide Impact

- **Interaction graph:** Selection ops → `WorkspaceSelectionMutationService` (ContextCore, already linked); prompt export → `PromptPackagingService`/`PromptContextPreAssemblyService` (ContextCore) → file; oracle tools → `OracleService` persisted `chats/` JSON; `agent_explore` → `HeadlessAgentSessionManager` spawn machinery with a read-only agent template.
- **Error propagation:** Oracle auth errors (`RPCE_ORACLE_API_KEY` absent) must surface consistently across the family (same message as `OpenAICompatibleClient.swift:118`). Failed oracle sends must not persist partial session files. Path-traversal errors on export must reject before any file write.
- **State lifecycle risks:** Selection `preview` must not mutate `self.selection` (non-mutating dry-run). Oracle `new_chat:true` must ignore `chat_id` and create a fresh session. `select_preset` sets an in-memory active preset that persists for subsequent `workspace_context`/`export` calls. `agent_explore` stopgap sessions are ephemeral (same as `agent_run` today).
- **API surface parity:** `manage_selection` gains `slices`/`preview`/`promote`/`demote`; `prompt` gains `export`/`list_presets`/`select_preset`; new `oracle_chat_log` + `oracle_utils` tools; `oracle_send` gains `mode`/`new_chat`/`export_response`; new `agent_explore` tool (stopgap). Schema descriptions in `HeadlessToolSchemas.swift` must be updated (remove "Unsupported in headless v1") so clients learn the right contract.
- **Integration coverage:** Export file readable and contains expected sections; oracle send → chat_log round-trip; selection preview does not mutate; `agent_explore` read-only enforcement proven via sandbox integration test.
- **Unchanged invariants:** The existing `manage_selection` `get`/`add`/`remove`/`set`/`clear` ops and `prompt` `get`/`set`/`append`/`clear` ops remain unchanged. The existing `oracle_send` contract (without the new optional args) remains backward-compatible. `agent_run` is unchanged (the stopgap is a separate tool).

---

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| Oracle API key/auth surface inconsistency across the family | All family tools surface the same auth error message as `OpenAICompatibleClient.swift:118`; failed sends don't persist partial sessions (verify `OracleService.save` is only called on stream success after U3 enhancements). |
| Selection-store invariant drift (e.g. `codemapAutoEnabled` flips, `set` with `mode=slices` preserves unrelated files) | The engine (`WorkspaceSelectionMutationService`) is shared — invariants come for free *if* the headless wiring calls the same methods with the same arguments. Add parity tests that run identical inputs through both the app's path and the headless parser and diff results. |
| Prompt export path traversal | Reject paths escaping loaded roots before any file write; use the shared `writeExportFile` helper with root-scoped resolution. |
| `agent_explore` false-parity trap (callers assume app parity) | `headless_capabilities` reports `agent_explore` as `stopgap`/`limited` with an explicit absent-capabilities list; tool description says "headless read-only probe stopgap; no parent-session ownership, no worktree inheritance, no interactive wait." |
| Cross-leaf coupling via export file-write helper (U2 + U3) | Build `writeExportFile(path:content:)` once on `HeadlessWorkspaceHost` and share; otherwise two divergent path-resolution/traversal-protection implementations. |
| `HeadlessToolSchemas` enum drift (schemas accept ops but host throws) | After wiring, update schema descriptions to remove "Unsupported in headless v1" so clients don't learn the wrong contract. |

---

## Open Questions

### Resolved During Planning

- **Extend headless oracle vs port app `OracleViewModel`:** extend — the headless `OracleService` is self-contained; porting the app oracle drags in `PromptViewModel`/`WindowManager`/`GlobalSettingsStore`.
- **Preset-less export v1:** yes — reuse `workspaceContext` rendering → write file; delivers value without a preset model.
- **`agent_explore` stopgap framing:** ship a constrained read-only probe under the `agent_explore` name with explicit limitations documented; full port deferred to post-Lanes-1–2.
- **`ask_oracle` as a separate tool:** no — `oracle_send` covers the use case; reserving the name avoids a false-parity trap.

### Deferred to Implementation

- **Headless-local preset config-file override:** whether v1 reads an env/config file for user-defined presets beyond the built-ins, or built-ins only.
- **`RPCE_ORACLE_MODELS` env CSV for `oracle_utils models` catalog:** v1 returns the default model only; richer catalog deferred.
- **Whether to share `parseManageSelectionInputs` back into ContextCore:** recommendation is NOT (keep headless-local), but the decision can be revisited during implementation.
- **Full `agent_explore` port post-Lanes-1–2:** re-scope against the new substrate once Lane 1 lands.

---

## Documentation / Operational Notes

- Update `Sources/RepoPromptHeadlessServer/README.md` with the new `manage_selection` ops, `prompt` presets/export, oracle family tools, and `agent_explore` stopgap.
- Document `agent_explore` stopgap limitations explicitly in `headless_capabilities` output and tool description.
- Parity map rows (Lane 0) owned by Lane 5 flip to `ported` as units land: selection slices/preview/promote/demote (U1), prompt presets/export (U2), oracle family (U3). The `agent_explore` row stays `partial`/`deferred` until the full port lands post-Lanes-1–2.
- Document that headless presets are rendering-only (no model/chat-preset binding, unlike the app's `CopyPreset`) — name them distinctly or document the scope difference in `headless_capabilities`.

---

## Sources & References

- **Origin document:** [docs/investigations/feature-parity/app-vs-headless-parity-design.md](docs/investigations/feature-parity/app-vs-headless-parity-design.md) (§1 raw gap, §6 gap matrix read-side rows)
- **Lane index:** [2026-06-18-001-feat-app-headless-parity-lane-index-plan.md](2026-06-18-001-feat-app-headless-parity-lane-index-plan.md)
- **App reference (selection):** `Sources/RepoPrompt/Infrastructure/MCP/WindowTools/MCPSelectionToolProvider.swift`
- **Shared selection engine:** `Sources/RepoPromptContextCore/WorkspaceContext/Selection/WorkspaceSelectionMutationService.swift`, `StoredSelection.swift`
- **App reference (prompt):** `Sources/RepoPrompt/Infrastructure/MCP/WindowTools/MCPPromptContextToolProvider.swift`, `Sources/RepoPrompt/Features/Prompt/Models/Copy/CopyPreset.swift`
- **Shared prompt rendering:** `Sources/RepoPromptContextCore/PromptServices/PromptPackagingService.swift`, `PromptContextPreAssemblyService.swift`, `PromptContextAccountingService.swift`
- **App reference (oracle):** `Sources/RepoPrompt/Infrastructure/MCP/WindowTools/MCPOracleToolProvider.swift`, `Sources/RepoPrompt/Infrastructure/MCP/MCPOracleToolService.swift`, `Sources/RepoPrompt/Features/Chat/ViewModels/Oracle/OracleViewModel+MCP.swift`
- **Headless oracle (extend):** `Sources/RepoPromptHeadlessServer/OracleService.swift`, `OracleSendTool.swift`, `OpenAICompatibleClient.swift`
- **App reference (agent_explore):** `Sources/RepoPrompt/Infrastructure/MCP/WindowTools/MCPAgentControlToolProvider.swift`, `Sources/RepoPrompt/Infrastructure/MCP/Agent/AgentExploreMCPToolService.swift`
- **Headless current-state:** `Sources/RepoPromptHeadlessServer/HeadlessWorkspaceHost.swift` (selection/prompt rejections), `HeadlessToolSchemas.swift`, `HeadlessAgentSessionManager.swift`, `AgentLauncher.swift`
- **AGENTS.md oracle env config:** `RPCE_ORACLE_API_KEY`/`OPENROUTER_API_KEY`/`RPCE_ORACLE_BASE_URL`/`RPCE_ORACLE_MODEL`
