# Plan 003: Build `rpce-headless` — a standalone MCP server exposing the deterministic context tools

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 1db9bbc..HEAD -- Sources/RepoPrompt/Infrastructure/MCP Sources/RepoPromptMCP Package.swift`
> Plan 002 intentionally changed `Package.swift` and moved engine code into
> `Sources/RepoPromptContextCore/` — that is expected drift. Anything else
> mismatching the excerpts below → STOP.

## Status

- **Priority**: P1
- **Effort**: L
- **Risk**: MED
- **Depends on**: plans/002-carve-out-contextcore.md (DONE required)
- **Category**: direction (new capability)
- **Planned at**: commit `1db9bbc`, 2026-06-11
- **Completed at**: 2026-06-11
- **Result**: DONE — implemented `rpce-headless` stdio MCP server with seven deterministic tools.
- **Validation**:
  - `swift build --product rpce-headless` — passed (direct build run by orchestrator; coordinated conductor product allowlist does not yet include `rpce-headless`).
  - `make dev-swift-build PRODUCT=RepoPrompt` — passed (ticket `3f924b05-867a-450b-bb23-20a39fda033a`).
  - `make dev-test FILTER=WorkspaceFileContextStoreTests` — passed, 112 tests, 0 failures (ticket `d4bc0965-076f-40e2-9ceb-ee22127cb39e`).
  - `python3 Sources/RepoPromptHeadlessServer/Scripts/mcp_smoke.py .build/debug/rpce-headless "$PWD"` — passed (`INIT OK`, `ALL OK`).
- **Notes**:
  - `make dev-swift-build PRODUCT=rpce-headless` currently fails before build because `conductor swift-build --product` only allows `RepoPrompt`, `repoprompt-mcp`, and `all`; direct SwiftPM build was used for the new product.
  - Smoke tree assertion uses an explicit loaded-root `path` with `mode:"full"` because the extracted engine's unscoped auto-depth tree is a directory overview and may omit root files.
  - Headless v1 returns explicit unsupported tool errors for selection slices, `preview`, `promote`, `demote`, and prompt preset/export operations.

## Why this matters

Today the only MCP server is the macOS app: the `repoprompt-mcp` binary is a
pure stdio↔unix-socket proxy that forwards every frame to the running app
and implements zero tools itself (its mode dispatch is shown below). The goal
of this fork is to run RepoPrompt's context tools on a Linux VPS with no app.
This plan creates a new executable, `rpce-headless`, that serves MCP directly
over stdio using the engine library from plan 002, with a single-workspace
model replacing the app's window/tab routing. After this plan, any MCP host
(Claude Code, Codex, a script) can use the seven deterministic tools against
a repo on disk with no GUI anywhere.

## Current state

- Proxy-mode dispatch in `Sources/RepoPromptMCP/main.swift:2740-2774`
  (verified): `switch mode { case .proxy: ... service = MCPService() ... }` —
  `MCPService` bridges stdio to the app's socket; there is no local tool
  hosting. You are NOT modifying this binary; it's listed so you understand
  what `rpce-headless` is replacing.
- App-side MCP server construction (your reference for building an
  `MCP.Server` with the pinned SDK): `Sources/RepoPrompt/Infrastructure/MCP/BootstrapSocketConnectionManager.swift:81-118`
  wraps an FD in a transport and constructs the `MCP.Server`. Read it before
  Step 3. The MCP SDK is pinned at `Package.swift:19`
  (`provencher/swift-sdk`, revision `85dec2fc...`).
- App-side tool implementations to mirror (read each before implementing the
  corresponding tool; copy their input schemas and reply shapes):
  - `Sources/RepoPrompt/Infrastructure/MCP/WindowTools/MCPSelectionToolProvider.swift` — `manage_selection` (`manageSelectionTool()` ~line 22; execution ~lines 99–219)
  - `Sources/RepoPrompt/Infrastructure/MCP/WindowTools/MCPFileToolProvider.swift` — `get_code_structure` (~lines 78–172) and `get_file_tree` (~lines 171–278)
  - `Sources/RepoPrompt/Infrastructure/MCP/ViewModels/MCPServerViewModel+WorkspaceContext.swift` — `workspace_context` assembly (~lines 3–213)
  - DTO shapes: `Sources/RepoPrompt/Infrastructure/MCP/ToolResultDTOs.swift`
- The app's dependency seam these providers consume —
  `Sources/RepoPrompt/Infrastructure/MCP/WindowTools/MCPWindowToolDependencies.swift:4-8`
  (verified):

  ```swift
  /// Constructor-time dependency bundle for extracted window-tool providers.
  ///
  /// Providers receive narrow services/closures instead of an
  /// `MCPServerViewModel` reference.
  struct MCPWindowToolDependencies {
  ```

  …but the bundle still stores app view models (verified, lines 224–227:
  `windowID`, `promptVM: PromptViewModel`,
  `workspaceManager: WorkspaceManagerViewModel?`,
  `selectionCoordinator: WorkspaceSelectionCoordinator?`). **Do not port this
  struct.** Write a small headless equivalent (Step 2) and fresh, narrow tool
  handlers that call `RepoPromptContextCore` services directly. The app
  providers are your reference for schemas/semantics, not code to reuse.
- Engine services now in `RepoPromptContextCore` (post-002 paths):
  - `WorkspaceContext/WorkspaceFileContextStore.swift` — file catalog, snapshots (file-tree snapshot entry points ~lines 1344–1470 pre-move), ingress
  - `WorkspaceContext/Selection/WorkspaceSelectionMutationService.swift` — selection mutations over the store
  - `Search/StoreBackedWorkspaceSearch.swift` + `WorkspaceContext/Search/WorkspaceSearchService.swift` — search
  - `CodeMap/CodeMapExtractor+Snapshots.swift` — store-backed tree/codemap rendering
  - `WorkspaceContext/TokenAccounting/TokenCalculationService.swift` — token estimates
  - `PromptServices/PromptPackagingService.swift`, `PromptContextPreAssemblyService.swift` — context block rendering

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Build server | `swift build --product rpce-headless` | exit 0 |
| Build app (regression) | `swift build --product RepoPrompt` | exit 0 |
| Run server | `.build/debug/rpce-headless serve --root <abs path>` | waits on stdio |
| Protocol test | `python3 /tmp/rpce_mcp_test.py .build/debug/rpce-headless <repo>` | prints `ALL OK` |

## Scope

**In scope**:
- `Package.swift` (new executable target/product `rpce-headless`, name the target `RepoPromptHeadlessServer`, path `Sources/RepoPromptHeadlessServer`)
- `Sources/RepoPromptHeadlessServer/**` (all new files)
- Minimal additional `public` modifiers inside `Sources/RepoPromptContextCore/**` when the compiler demands them
- `plans/README.md` (status)

**Out of scope** (do NOT touch):
- `Sources/RepoPromptMCP/**` (the proxy keeps working against the Mac app)
- `Sources/RepoPrompt/**` (app behavior unchanged)
- Multi-workspace/multi-tab semantics, `bind_context`, `apply_edits`/file
  mutation tools, `git` tool, agent tools — all deferred
- Any networking; this plan is stdio-only (the unix socket comes in plan 006)

## Git workflow

- Branch: `headless/003-server`
- Commit per step; subject style: short imperative.
- Preflight note: same as plan 002 (run the contribution-check script; on
  allowlist failures proceed with a note; on secret findings STOP).

## Steps

### Step 1: Target + CLI skeleton

Add to `Package.swift`:

```swift
.executable(name: "rpce-headless", targets: ["RepoPromptHeadlessServer"]) // in products
.executableTarget(
    name: "RepoPromptHeadlessServer",
    dependencies: [
        "RepoPromptContextCore", "RepoPromptShared",
        .product(name: "Logging", package: "swift-log"),
        .product(name: "MCP", package: "swift-sdk"),
        .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
        .product(name: "SystemPackage", package: "swift-system"),
    ],
    path: "Sources/RepoPromptHeadlessServer",
    swiftSettings: [.define("DEBUG", .when(configuration: .debug))]
),
```

`main.swift`: parse `serve --root <path> [--root <path> ...]` by hand from
`CommandLine.arguments` (no ArgumentParser dependency). Unknown args → print
usage to stderr, exit 64. Resolve each root to an absolute path; nonexistent
root → stderr message, exit 66.

**Verify**: `swift build --product rpce-headless` → exit 0;
`.build/debug/rpce-headless` (no args) → usage on stderr, exit 64.

### Step 2: `HeadlessWorkspaceHost`

New file `Sources/RepoPromptHeadlessServer/HeadlessWorkspaceHost.swift`: an
`actor` owning the engine state for ONE workspace:

- the `WorkspaceFileContextStore` (find its initializer with
  `grep -rn "= WorkspaceFileContextStore(" Sources/RepoPrompt Sources/RepoPromptContextCore`
  and mirror the simplest app construction; pass the root paths from the CLI)
- a selection (whatever value type `WorkspaceSelectionMutationService`
  produces/consumes — read that file first; it is Foundation-only)
- prompt state: `var promptText: String = ""`
- a fixed identity: `let tabID = UUID()` (single implicit "tab"; tools that
  app-side require tab context just use this)

Expose async methods the tool layer will call: `fileTree(mode:path:maxDepth:)`,
`search(...)`, `codeStructure(paths:)`, `readFile(path:start:limit:)`,
`selection* (get/add/remove/set/clear)`, `workspaceContext(include:)`,
`promptGet()/promptSet(_:)` — each a thin delegation to the ContextCore
services named in Current state. Build incrementally; leave methods
`fatalError("unimplemented")` until their step.

The store must be populated before serving: mirror how the app triggers the
initial catalog build/ingress (look at call sites of the store's
load/ingress methods found via
`grep -rn "awaitAppliedIngress\|WorkspaceFileSystemIngressCoordinator" Sources/RepoPromptContextCore | head`,
then find the app-side bootstrapper that kicks it off). If initial population
turns out to require an app type that didn't move in 002 → STOP and report
the type.

**Verify**: `swift build --product rpce-headless` → exit 0. Add a temporary
`dump` subcommand that constructs the host, awaits population, prints the
number of cataloged files for `--root`, exits 0 — run it against this repo
and confirm a plausible nonzero count. Keep `dump` (it's a useful diagnostic).

### Step 3: MCP server over stdio

Read `Sources/RepoPrompt/Infrastructure/MCP/BootstrapSocketConnectionManager.swift:81-118`
for `MCP.Server` construction with this SDK revision. Create
`Sources/RepoPromptHeadlessServer/HeadlessMCPServer.swift`:

- Construct `MCP.Server` (name `"rpce-headless"`, version from a constant).
- Use the SDK's stdio transport if it provides one
  (`grep -rn "StdioTransport\|class.*Transport" .build/checkouts/swift-sdk/Sources/MCP | head -20`
  — checkouts exist after any build). If the pinned SDK has no stdio server
  transport, copy the app's `UnixSocketMCPTransport` approach but reading
  fd 0 / writing fd 1 (newline-delimited JSON-RPC), placed in
  `Sources/RepoPromptHeadlessServer/StdioMCPTransport.swift`.
- Register `tools/list` + `tools/call` handlers for exactly these seven
  tools: `read_file`, `get_file_tree`, `file_search`, `get_code_structure`,
  `manage_selection`, `workspace_context`, `prompt`. Copy each tool's `Tool`
  name/description/inputSchema from the app provider files listed in Current
  state, simplified where a parameter is window/tab-specific (drop
  `window_id`-style params; single workspace).

**Verify**: write `/tmp/rpce_mcp_test.py` with the harness below, then:
`python3 /tmp/rpce_mcp_test.py .build/debug/rpce-headless /Users/ben/code/repoprompt-ce --phase init`
→ prints `INIT OK` and the seven tool names.

```python
#!/usr/bin/env python3
# Minimal MCP stdio harness: initialize -> tools/list -> per-tool calls.
import json, subprocess, sys, itertools
binary, root = sys.argv[1], sys.argv[2]
phase = sys.argv[4] if len(sys.argv) > 4 else (sys.argv[3].split("=",1)[1] if len(sys.argv)>3 and sys.argv[3].startswith("--phase=") else (sys.argv[4] if "--phase" in sys.argv else "all"))
p = subprocess.Popen([binary, "serve", "--root", root], stdin=subprocess.PIPE,
                     stdout=subprocess.PIPE, stderr=sys.stderr, text=True)
ids = itertools.count(1)
def rpc(method, params=None):
    i = next(ids)
    p.stdin.write(json.dumps({"jsonrpc":"2.0","id":i,"method":method,"params":params or {}})+"\n"); p.stdin.flush()
    while True:
        line = p.stdout.readline()
        if not line: sys.exit("server closed stdout")
        msg = json.loads(line)
        if msg.get("id") == i:
            assert "error" not in msg, f"{method} -> {msg['error']}"
            return msg["result"]
def notify(method, params=None):
    p.stdin.write(json.dumps({"jsonrpc":"2.0","method":method,"params":params or {}})+"\n"); p.stdin.flush()
init = rpc("initialize", {"protocolVersion":"2024-11-05","capabilities":{},
                          "clientInfo":{"name":"harness","version":"0"}})
notify("notifications/initialized")
tools = {t["name"] for t in rpc("tools/list")["tools"]}
expected = {"read_file","get_file_tree","file_search","get_code_structure",
            "manage_selection","workspace_context","prompt"}
assert expected <= tools, f"missing: {expected - tools}"
print("INIT OK", sorted(tools))
if phase != "init" and "all" in (phase,):
    def call(name, args):
        r = rpc("tools/call", {"name": name, "arguments": args})
        text = "".join(c.get("text","") for c in r.get("content",[]))
        assert not r.get("isError"), f"{name} errored: {text[:400]}"
        return text
    assert "Package.swift" in call("get_file_tree", {"max_depth": 1})
    assert "RepoPromptContextCore" in call("file_search", {"pattern":"RepoPromptContextCore","max_results":5})
    assert "swift-tools-version" in call("read_file", {"path":"Package.swift","start_line":1,"limit":3})
    assert "struct" in call("get_code_structure", {"paths":["Sources/RepoPromptShared/MCP/MCPControlMessages.swift"]}).lower()
    call("manage_selection", {"op":"add","paths":["Package.swift"]})
    assert "Package.swift" in call("manage_selection", {"op":"get","view":"files"})
    call("prompt", {"op":"set","text":"hello prompt"})
    assert "hello prompt" in call("prompt", {"op":"get"})
    wc = call("workspace_context", {})
    assert "Package.swift" in wc
    print("ALL OK")
p.stdin.close(); p.wait(timeout=10)
```

### Step 4: Implement the tools (one commit each)

Implement in this order, running the harness's relevant assertion after each:
1. `read_file` (host → `WorkspaceReadableFileService` or direct store read; honor `start_line`/`limit`, negative tail like the app's tool description)
2. `get_file_tree` (store snapshot rendering via `CodeMapExtractor+Snapshots` path; support `mode`, `path`, `max_depth`; default `auto` may simply map to `full` for v1 — note it in the tool description)
3. `file_search` (delegate to `WorkspaceSearchService`/`StoreBackedWorkspaceSearch`; support `pattern`, `mode`, `regex`, `max_results`, `filter.extensions`, `filter.paths`, `context_lines`)
4. `get_code_structure` (codemap extraction for given paths)
5. `manage_selection` (`get/add/remove/set/clear`, `view` summary/files; slices may return "unsupported in v1" errors — document in schema description)
6. `prompt` (`get`/`set` on host state)
7. `workspace_context` (assemble file tree + selected file contents + prompt via `PromptPackagingService`/`PromptContextPreAssemblyService`, mirroring `MCPServerViewModel+WorkspaceContext.swift` minus git-diff and tab branches; include token totals from `TokenCalculationService`)

**Verify after each**: `swift build --product rpce-headless` → exit 0, then
the harness. After tool 7: full harness → `ALL OK`.

### Step 5: Regression + docs

1. `swift build --product RepoPrompt` → exit 0 (app unaffected).
2. `swift test --filter WorkspaceFileContextStoreTests` → pass.
3. Add `Sources/RepoPromptHeadlessServer/README.md` (one page: build, serve,
   harness usage, tool list, single-workspace semantics, what's deferred).

## Test plan

- The Python harness is the integration test; check it in as
  `Sources/RepoPromptHeadlessServer/Scripts/mcp_smoke.py` (same content as
  `/tmp/rpce_mcp_test.py`) so CI/humans can rerun it.
- New unit tests are NOT required for v1 (handlers are thin delegations);
  the engine keeps its existing suite.

## Done criteria

- [ ] `swift build --product rpce-headless` exits 0
- [ ] `python3 Sources/RepoPromptHeadlessServer/Scripts/mcp_smoke.py .build/debug/rpce-headless "$PWD"` prints `ALL OK`
- [ ] `swift build --product RepoPrompt` exits 0
- [ ] `swift test --filter WorkspaceFileContextStoreTests` passes
- [ ] No files outside the in-scope list modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- `WorkspaceFileContextStore` cannot be constructed/populated without an app
  type that plan 002 left behind (name the type and the initializer signature
  you found).
- The pinned MCP SDK revision has neither a stdio server transport nor
  enough public surface to write one (report what `Server`/`Transport` APIs
  exist in `.build/checkouts/swift-sdk`).
- `workspace_context` assembly requires `PromptViewModel` state with no
  ContextCore equivalent after one honest attempt at substitution.
- Harness deadlocks (server never answers `initialize`) after two debugging
  attempts — capture stderr and report.

## Maintenance notes

- The host is single-workspace by design; multi-workspace = run N processes.
  If multi-tab semantics are ever needed, revisit before adding tools that
  assume tab identity.
- Plan 004 makes this target build on Linux; avoid adding new
  Darwin-only API to this target (keep platform code in ContextCore behind
  the seams 004 introduces).
- Deferred: `git` tool, `apply_edits`, slices support in `manage_selection`,
  auto-codemap behavior, multi-client socket serving (plan 006 adds the
  socket listener).
