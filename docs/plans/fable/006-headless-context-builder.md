# Plan 006: Add headless `context_builder` — pluggable discovery agent over the server's own tools

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: confirm plans 003 (and ideally 005) are DONE;
> `mcp_smoke.py` prints `ALL OK`.

## Status

- **Priority**: P2
- **Effort**: L
- **Risk**: MED-HIGH (subprocess orchestration + external CLIs; mitigated by a fully offline fake-agent gate)
- **Depends on**: plans/003 (required), plans/005 (only for the optional answer/plan follow-up step), plans/004 (only for running on Linux)
- **Category**: direction (new capability)
- **Planned at**: commit `1db9bbc`, 2026-06-11
- **Completed**: 2026-06-11 — macOS/offline fake-agent path implemented and validated. Linux execution remains blocked by plan 004, which inherits the plan-001 Docker daemon blocker.

## Completion notes

- Implemented Unix socket serving for `rpce-headless serve --socket`, with all socket connections restricted to the discovery allowlist (`manage_selection`, `prompt`, `workspace_context`, `get_file_tree`, `get_code_structure`, `file_search`, `read_file`).
- Added `rpce-headless connect --socket` as the stdio↔Unix-socket bridge for agent MCP configs. Stdio serving remains unrestricted and includes `oracle_send`.
- Added pluggable agent config rendering, dry-run output, generated MCP config, Discover prompt builder, `context-build` orchestration/harvest, and offline fake-agent acceptance coverage.
- Added `Sources/RepoPromptHeadlessServer/Examples/agents.json` with `claude`, `fake`, and UNVERIFIED `pi` starting templates. Pi remains documented as requiring `pi-mcp-adapter`.
- Did not modify app AgentMode machinery, ContextBuilderAgentViewModel, AgentRuntimeProviderService, or `Sources/RepoPromptMCP/**`.

## Why this matters

`context_builder` is RepoPrompt's signature feature: an LLM "discovery agent"
autonomously explores the repo through the context tools and leaves behind a
curated file selection + handoff prompt. In the app, the orchestration shell
is a `@MainActor` view model, but the architecture is already an
external-process contract: the app spawns an agent CLI, restricts its MCP
tools to a discovery set, and harvests the resulting selection/prompt state.
This plan re-creates that contract in `rpce-headless` with a **pluggable
agent command** — Claude Code, Codex, OpenCode, or Pi — so any model can do
discovery on the VPS. The orchestrator is verifiable offline with a scripted
fake agent; real CLIs are config.

## Current state

(App references = semantics to mirror; none of these files are modified.)

- The app's shell obtains the agent via
  `Sources/RepoPrompt/Features/ContextBuilder/ViewModels/ContextBuilderAgentViewModel.swift:819`:
  `AgentRuntimeProviderService.shared.makeProvider(` → returns a
  `HeadlessAgentProvider`. The provider protocol (verified, full):
  `Sources/RepoPrompt/Features/AgentMode/Providers/HeadlessAgentProvider.swift:4-13` —
  `streamAgentMessage(_ message: AgentMessage, runID: UUID?) async throws -> AsyncThrowingStream<AIStreamResult, Error>` + `dispose()`.
  Runtime kinds at `Sources/RepoPrompt/Features/AgentMode/Runtime/Providers/AgentRuntimeProviderService.swift:54-74`:
  `.claudeCode/.claudeCodeGLM/.kimiCode/.customClaudeCompatible` → "Claude Code",
  `.codexExec` → "Codex CLI", `.openCode` → "OpenCode", `.cursor` → "Cursor CLI".
  **We do not port this machinery** — for headless v1 the "provider" is just a
  configured argv template (Step 2); the protocol matters only as background.
- Tool restriction: the app applies `DiscoverMCPToolPolicy.restrictedTools`
  (`ContextBuilderAgentViewModel.swift:2078`). The policy file
  (`Sources/RepoPrompt/Infrastructure/MCP/Policies/DiscoverMCPToolPolicy.swift`,
  verified, full file) restricts by capability sets. For headless we invert
  it to a hardcoded **allowlist**, matching the discovery toolset observed in
  the live Discover prompt: `manage_selection`, `prompt`, `workspace_context`,
  `get_file_tree`, `get_code_structure`, `file_search`, `read_file`
  (the app also allows `git`; we haven't built a `git` tool — omit).
- The Discover system prompt template lives in
  `Sources/RepoPrompt/Infrastructure/AI/SystemPromptService.swift` (contains
  the literal "curate the perfect file selection" — find the builder function
  around that string). It is long (~4–5k words) and parameterized by token
  budget and response mode.
- The proxy binary already contains a working stdio↔unix-socket bridge you
  can mirror for the `connect` subcommand:
  `Sources/RepoPromptMCP/main.swift` around lines 476–481
  (`BootstrapSocketProxy.runBridge`), plus
  `Sources/RepoPromptMCP/Shared/NewlineDelimitedSocketReader.swift` and
  `Sources/RepoPromptMCP/Transports/NonBlockingFDWriter.swift`. Copy what you
  need into the server target rather than adding a target dependency on an
  executable (SwiftPM forbids that).

Flow you are building:

```
rpce-headless context-build --root R --instructions "…" [--response-type selection|question|plan]
  1. host serves MCP on a unix socket /tmp/rpce-headless-<pid>.sock (discovery allowlist enforced)
  2. write Discover prompt to a temp file; render the agent argv template
  3. spawn agent subprocess (inherits env + RPCE_* vars); agent's MCP config
     points at `rpce-headless connect --socket <path>`
  4. agent explores via tools; mutates selection + prompt state
  5. on agent exit: harvest selection summary + prompt text; if
     --response-type question|plan and plan 005 present: run oracle_send over
     the result; print report to stdout; exit 0
```

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Build | `swift build --product rpce-headless` | exit 0 |
| Offline E2E | `python3 Sources/RepoPromptHeadlessServer/Scripts/context_build_fake_agent_test.py .build/debug/rpce-headless "$PWD"` | `CONTEXT_BUILD OK` |
| Real-agent E2E (optional) | `.build/debug/rpce-headless context-build --root "$PWD" --instructions "Map the MCP server entry points" --agent claude` | non-empty selection report |
| Regression | `mcp_smoke.py` | `ALL OK` |

## Scope

**In scope**:
- `Sources/RepoPromptHeadlessServer/**` (new: `UnixSocketListener.swift`,
  `ConnectBridge.swift` (the `connect` subcommand), `DiscoverPromptBuilder.swift`,
  `AgentLauncher.swift`, `ContextBuildCommand.swift`, fake-agent test script,
  example agent config)
- Moving/copying the Discover prompt builder out of
  `SystemPromptService.swift` into ContextCore or the server target (copying
  the template string is acceptable on this fork; if you move it, app must
  still build)
- `plans/README.md`

**Out of scope** (do NOT touch):
- `ContextBuilderAgentViewModel`, `AgentRuntimeProviderService`, any AgentMode
  runtime (app machinery stays)
- Implementing a `git` MCP tool, approvals/permissions UX, multi-tab binding
- Auto-installing agent CLIs; they're operator-provided

## Git workflow

- Branch: `headless/006-context-builder`. Commit per step. Same preflight
  note as plan 002.

## Steps

### Step 1: Unix-socket serving + `connect` bridge

1. `UnixSocketListener.swift`: AF_UNIX/SOCK_STREAM listener (SystemPackage or
   the POSIX helpers in `Sources/RepoPromptShared/MCP/POSIXDescriptorSupport.swift`),
   socket path `--socket <path>` (default `/tmp/rpce-headless-<pid>.sock`,
   mode 0600, unlinked on exit). Each accepted connection gets the SAME
   newline-delimited JSON-RPC handling as stdio serving, with a per-connection
   flag `discoveryRestricted: Bool`.
2. Tool gating: when `discoveryRestricted`, `tools/list` returns only the
   allowlist (Current state) and `tools/call` for anything else returns an
   `isError` result naming the restriction. For v1, mark **all** socket
   connections discovery-restricted (stdio remains unrestricted).
3. `connect` subcommand: `rpce-headless connect --socket <path>` pumps
   stdin→socket and socket→stdout verbatim (mirror the proxy's bridge files
   listed in Current state). This is what agent CLIs exec as their "MCP
   server" command.

**Verify**: start `serve --root "$PWD" --socket /tmp/t.sock` in one shell;
in another run the plan-003 harness against `connect`:
`python3 …/mcp_smoke.py ".build/debug/rpce-headless" "$PWD" ` won't fit its
argv shape — instead run:
`echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"0"}}}' | .build/debug/rpce-headless connect --socket /tmp/t.sock | head -1`
→ a JSON `result` line. Then confirm `tools/list` over the socket lacks
`oracle_send` (restriction works).

### Step 2: Agent command config

`AgentLauncher.swift` + example config installed at
`Sources/RepoPromptHeadlessServer/Examples/agents.json` (operator copies to
`~/.config/rpce-headless/agents.json`):

```json
{
  "claude": {
    "argv": ["claude", "-p", "{PROMPT}", "--mcp-config", "{MCP_CONFIG}",
             "--strict-mcp-config", "--permission-mode", "bypassPermissions"],
    "promptVia": "argv"
  },
  "fake": { "argv": ["python3", "{FAKE_AGENT_SCRIPT}", "{MCP_CONFIG_PATH_RAW}"], "promptVia": "env" }
}
```

Placeholders the launcher must substitute: `{PROMPT}` (the full Discover
prompt text), `{PROMPT_FILE}` (path to it), `{MCP_CONFIG}` (path to a
generated MCP config JSON: `{"mcpServers":{"repoprompt":{"command":"<abs path to rpce-headless>","args":["connect","--socket","<path>"]}}}`).
Exact CLI flags for real agents vary by version — the launcher must not
hardcode beyond the config file, and the config is operator-editable. The
prompt is also exported as env `RPCE_DISCOVER_PROMPT` for `promptVia: "env"`.

**Verify**: unit-ish check — add `rpce-headless context-build --dry-run …`
that prints the rendered argv + generated MCP config path without spawning;
assert placeholders are gone.

### Step 3: Discover prompt builder

Locate the builder in `SystemPromptService.swift` (search "curate the perfect
file selection"). Extract/copy into `DiscoverPromptBuilder.swift` with
parameters: `instructions: String`, `tokenBudget: Int` (default 118500 to
match the app), `responseType: selection|question|plan`. Strip app-only
sections if they reference tabs/windows/oracle UI. Keep the tool-usage
sections — they teach the agent the same seven tools the socket exposes
(adjust any mention of `git` to note it is unavailable).

**Verify**: `--dry-run` prints a prompt containing "curate the perfect file
selection" and the user's instructions verbatim.

### Step 4: `context-build` command + harvest

`ContextBuildCommand.swift`:
1. Start socket serving (Step 1) in-process.
2. Render prompt + config; spawn the agent (Foundation `Process`), streaming
   its stdout/stderr to the operator's stderr prefixed `agent|`.
3. Timeout `--timeout <sec>` (default 900): kill the process group on expiry.
4. On exit: read host state — selection file list w/ token counts, prompt
   text. Print a report to stdout:
   ```
   == context-build report ==
   agent exit: 0
   selection (N files, ~T tokens):
     <path>  <tokens>
   prompt:
   <prompt text>
   ```
5. `--response-type question|plan` (requires plan 005): call OracleService
   with the assembled workspace_context + the instructions, append `answer:`
   section to the report. If 005 absent, error out at arg-parse time.
6. Exit nonzero if agent exited nonzero OR selection is empty.

**Verify**: Step 5's fake-agent test.

### Step 5: Offline fake-agent E2E

`Sources/RepoPromptHeadlessServer/Scripts/context_build_fake_agent_test.py`:
spawns `rpce-headless context-build --root <repo> --agent fake --instructions "test"`,
where the `fake` agent (a python script this test writes to /tmp, path passed
through `{FAKE_AGENT_SCRIPT}` env or config) reads the MCP config JSON path
from argv, connects via the `connect` command shape found there, performs:
`initialize` → `tools/list` (assert allowlist, assert NO `oracle_send`) →
`file_search {pattern: "swift-tools-version"}` → `manage_selection {op:"add", paths:["Package.swift"]}`
→ `prompt {op:"set", text:"<taskname=\"Fake\"/> fake handoff"}` → exit 0.
The test then asserts the parent's stdout report contains `Package.swift`
and `fake handoff`, and exit code 0. Print `CONTEXT_BUILD OK`.

**Verify**: `python3 …/context_build_fake_agent_test.py .build/debug/rpce-headless "$PWD"` → `CONTEXT_BUILD OK`.

### Step 6 (optional, operator-run): real agent

If `claude` CLI is installed and authenticated: run the real-agent E2E from
the commands table. Record in README status whether it produced a non-empty
selection. For Pi: Pi has no built-in MCP; document in
`Sources/RepoPromptHeadlessServer/README.md` that Pi connects via the
`pi-mcp-adapter` extension with the same generated MCP config, and add a
commented `"pi"` entry to `Examples/agents.json` marked UNVERIFIED.

## Test plan

- `context_build_fake_agent_test.py` is the acceptance test (checked in).
- Covers: socket serving, tool allowlist enforcement, bridge round-trip,
  spawn/substitution, state harvest, report rendering, nonzero-exit
  propagation (add one case: fake agent exits 3 → parent exits nonzero).

## Done criteria

- [x] `swift build --product rpce-headless` exits 0 after rerun as `swift build --disable-sandbox --product rpce-headless` due the known SwiftPM sandbox failure in this environment.
- [x] `context_build_fake_agent_test.py` prints `CONTEXT_BUILD OK`.
- [x] Socket `tools/list` excludes `oracle_send` (restriction) while stdio includes it (post-005).
- [x] `mcp_smoke.py` still prints `ALL OK`.
- [x] `swift build --product RepoPrompt` not run; prompt builder was copied into the headless target, not moved from the app.
- [x] `plans/README.md` updated.

## STOP conditions

- The Discover prompt builder in `SystemPromptService.swift` is inseparable
  from app state (needs view models to render) after one honest attempt —
  fall back to copying the template literal; if even the literal references
  runtime app values you can't synthesize, STOP with the list of parameters.
- SwiftPM/socket layer: accepted-FD handling can't reuse the existing POSIX
  helpers and would need >200 new lines of raw C-interop — STOP and propose
  alternatives (e.g. TCP on localhost) instead of writing them.
- The fake-agent E2E deadlocks twice (capture both sides' last 20 lines).

## Maintenance notes

- The agent argv templates WILL rot as CLIs evolve — they're operator config
  by design; keep flags out of Swift.
- When a `git` MCP tool lands later, add it to the discovery allowlist and
  restore the prompt's git wording.
- Security: the socket is 0600 in /tmp and all socket connections are
  tool-restricted, but anything running as the same user can connect —
  acceptable for a single-user VPS; revisit before multi-tenant use.
- The report format is the seam a future `--json` output flag should hang off.
