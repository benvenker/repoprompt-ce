# Plan 010: Replace source-scraping schema tests with real `HeadlessToolSchemas` assertions

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `docs/plans/fable/README.md`.
>
> **Drift check (run first)**: `git diff --stat 0bd2270..HEAD -- Tests/RepoPromptTests/MCP/HeadlessAgentToolSchemaTests.swift Sources/RepoPromptHeadlessServer/HeadlessToolSchemas.swift Package.swift`
> On any drift, compare the "Current state" excerpts before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: S-M
- **Risk**: LOW-MED (one Package.swift dependency edit; linking an executable target into the test bundle — precedent exists in-repo)
- **Depends on**: none. Coordinate with plan 008 (it adds a `cancelling` enum value — see Step 3 note).
- **Category**: tests
- **Planned at**: commit `0bd2270`, 2026-06-12

## Why this matters

`HeadlessAgentToolSchemaTests` currently reads
`Sources/RepoPromptHeadlessServer/HeadlessToolSchemas.swift` **as a text
file** and regex-scrapes tool names and enum values out of the source code.
It never calls `HeadlessToolSchemas.tools` or anything the compiler built. It
therefore (a) violates the repository's TDD rule that tests call actual
implementation functions, (b) passes even if runtime tool registration is
broken, and (c) silently **skips** (`XCTSkip`) when the source file isn't
found from the test working directory. This plan replaces it with assertions
against the real compiled values, and tightens the schemas so `op` is
declared `required` (the handlers already reject a missing `op` at runtime —
the schema should say so).

## Current state

- `Tests/RepoPromptTests/MCP/HeadlessAgentToolSchemaTests.swift` (104 lines) —
  the anti-pattern, e.g.:

  ```swift
  private static func headlessToolSchemasSource() throws -> String {
      let relativePath = "Sources/RepoPromptHeadlessServer/HeadlessToolSchemas.swift"
      var directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
      for _ in 0 ..< 6 { ... }
      throw XCTSkip("Could not locate \(relativePath) from test working directory")
  }

  private static func toolNames(inFullToolsSource source: String) -> Set<String> {
      Set(matches(in: source, pattern: #"Tool\(\s*name:\s*\"([^\"]+)\""#))
  }
  ```

  The two test methods assert: full tools ⊇ the 8 pre-existing tools +
  `agent_run` + `agent_manage`, exclude `agent_explore`; discovery names
  exclude all three agent tools; `agent_run` op enum ==
  `["start","poll","wait","cancel"]`; `agent_manage` op enum ==
  `["list_agents","list_sessions","get_log","stop_session","cleanup_sessions"]`.
  These are the right assertions — keep them, just make them real.

- `Sources/RepoPromptHeadlessServer/HeadlessToolSchemas.swift:1-17`:

  ```swift
  import MCP

  enum HeadlessToolSchemas {
      static let discoveryToolNames: Set<String> = [
          "manage_selection", "prompt", "workspace_context", "get_file_tree",
          "get_code_structure", "file_search", "read_file"
      ]

      static var discoveryTools: [Tool] {
          tools.filter { discoveryToolNames.contains($0.name) }
      }
  ```

  The full `tools` array contains 11 tools. `agent_run`'s schema
  (lines 103-117) and `agent_manage`'s (lines 118-130) build their input
  schemas via local helpers `object(...)`/`string(...)` etc. The
  `context_builder` schema (lines 131-143) already passes
  `required: ["instructions"]` — so the `object` helper supports a
  `required:` parameter.

- `Package.swift:154-162` — `RepoPromptTests` already depends on two
  **executable** targets, so linking a third has precedent:

  ```swift
  .testTarget(
      name: "RepoPromptTests",
      dependencies: ["RepoPrompt", "RepoPromptContextCore", "RepoPromptMCP", "RepoPromptShared"],
      path: "Tests/RepoPromptTests",
  ```

  and `Tests/RepoPromptTests/MCP/Control/PersistentMCPResponseDeliveryTests.swift:1-4`
  does `@testable import RepoPromptMCP` (RepoPromptMCP is an
  `.executableTarget` with a top-level-code `main.swift`, same shape as
  `RepoPromptHeadlessServer` at `Package.swift:93-98` / `99-113`).

- Runtime handling of `op` (context for Step 2):
  `HeadlessAgentSessionManager.swift:94` defaults a missing `agent_run.op`
  to `"wait"`; `HeadlessAgentSessionManager.swift:110-112` rejects a missing
  `agent_manage.op` with an actionable error. The app-side schema requires
  `op` (`Sources/RepoPrompt/Infrastructure/MCP/WindowTools/MCPAgentControlToolProvider.swift:221`).

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Build | `make dev-swift-build PRODUCT=rpce-headless` | exit 0 |
| Focused tests | `make dev-test FILTER=HeadlessAgentToolSchemaTests` | all pass, 0 skipped |
| Smoke | `python3 Sources/RepoPromptHeadlessServer/Scripts/mcp_agent_smoke.py .build/debug/rpce-headless` | `AGENT MCP SMOKE OK` |
| Lint / format | `make dev-lint` / `make dev-format` | exit 0 |

## Scope

**In scope**:
- `Package.swift` (one dependency addition to `RepoPromptTests` only)
- `Tests/RepoPromptTests/MCP/HeadlessAgentToolSchemaTests.swift` (rewrite)
- `Sources/RepoPromptHeadlessServer/HeadlessToolSchemas.swift` (required-op only)

**Out of scope**:
- Creating a new library target. The cheap path (test-deps on the executable
  target) has in-repo precedent; extraction is the STOP-condition fallback,
  not the default.
- `HeadlessAgentSessionManager.swift` — keep the runtime `op ?? "wait"`
  default; declaring `op` required in the schema is a client-facing contract
  tightening, not a handler change.
- Any other tool's schema.

## Git workflow

- Branch: `codex/fable-headless-linux` (or child `fable/010-schema-tests`).
- Preflight before each commit: `.agents/skills/rpce-contribution-check/scripts/preflight.sh commit`
- No push without operator instruction.

## Steps

### Step 1: Link the headless target into the test bundle

`Package.swift:156`: add `"RepoPromptHeadlessServer"` to the
`RepoPromptTests` dependencies array.

**Verify**: `swift build --build-tests` (or `make dev-test FILTER=HeadlessAgentToolSchemaTests` which builds first) → compiles.
If linking fails because of the executable's top-level `main.swift`
(duplicate main / missing `-parse-as-library`), that is a STOP condition —
see below.

### Step 2: Declare `op` required

In `HeadlessToolSchemas.swift`, using the same `required:` parameter style
as `context_builder` (line ~140):
- `agent_run` input schema: add `required: ["op"]`.
- `agent_manage` input schema: add `required: ["op"]`.

Note: the `agent_run` handler keeps its `"wait"` default for lenient
callers; the schema simply documents the contract MCP clients should follow
(matching the app-side schema).

**Verify**: `make dev-swift-build PRODUCT=rpce-headless` → exit 0;
`python3 Sources/RepoPromptHeadlessServer/Scripts/mcp_agent_smoke.py .build/debug/rpce-headless` → `AGENT MCP SMOKE OK`.

### Step 3: Rewrite the test against compiled values

Rewrite `HeadlessAgentToolSchemaTests.swift`:

- `@testable import RepoPromptHeadlessServer` (plus `import MCP`).
- Delete `headlessToolSchemasSource()`, `toolNames(inFullToolsSource:)`,
  `discoveryToolNames(in:)`, `opEnumValues(forToolNamed:in:)`, and
  `matches(in:pattern:)` — no file reads, no regex, no `XCTSkip`.
- Re-express the same assertions on real values:
  - `let names = Set(HeadlessToolSchemas.tools.map(\.name))` — assert the 8
    pre-existing tools, `agent_run`, `agent_manage` present;
    `agent_explore` absent. Also assert the exact full set has 11 members
    (catches accidental additions).
  - `Set(HeadlessToolSchemas.discoveryTools.map(\.name)) == HeadlessToolSchemas.discoveryToolNames`
    and that set excludes all three agent tool names.
  - Op enums: avoid guessing the `MCP.Value` accessor API — the headless
    target only ever constructs `Value` trees, never reads them, so there is
    no in-repo accessor pattern to copy. Instead round-trip through JSON
    (`Value` is `Codable`; it serializes into `tools/list` responses):

    ```swift
    private func schemaJSON(for tool: Tool) throws -> [String: Any] {
        let data = try JSONEncoder().encode(tool.inputSchema)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    ```

    Then navigate plain dictionaries: `schema["properties"]` → `["op"]` →
    `["enum"] as? [String]`. Assert the two op-enum equalities from the old
    test. (If `MCP.Value` turns out not to be `Encodable`, that is a STOP
    condition — report, don't improvise reflection.)
  - New (from Step 2): assert both tools' schemas declare
    `required == ["op"]` via the same JSON navigation.

**Verify**: `make dev-test FILTER=HeadlessAgentToolSchemaTests` → all tests
pass, none skipped.

If plan 008 already landed, the `state` filter enum contains `cancelling` —
do not assert on the `state` enum at all (it isn't asserted today either);
only `op` enums and `required` arrays.

## Test plan

The rewritten test IS the deliverable. Cases: full tool-name set (exact, 11),
discovery subset equality + agent-tool exclusion, both op enums exact, both
`required: ["op"]` declarations present. Pattern to follow for file layout:
the existing test file's two-method structure; for `@testable` executable
import precedent: `Tests/RepoPromptTests/MCP/Control/PersistentMCPResponseDeliveryTests.swift:1-4`.

## Done criteria

- [ ] `make dev-test FILTER=HeadlessAgentToolSchemaTests` exits 0, tests > 0, skipped == 0
- [ ] `grep -n "XCTSkip\|NSRegularExpression\|contentsOf" Tests/RepoPromptTests/MCP/HeadlessAgentToolSchemaTests.swift` → no matches
- [ ] `grep -n "required: \[\"op\"\]" Sources/RepoPromptHeadlessServer/HeadlessToolSchemas.swift` → 2 matches
- [ ] `make dev-swift-build PRODUCT=rpce-headless` exits 0; `mcp_agent_smoke.py` prints `AGENT MCP SMOKE OK`
- [ ] No files outside the in-scope list modified (`git status`)
- [ ] `docs/plans/fable/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- Step 1's link fails (duplicate `main`, Linux-only `await` in top-level
  code, or any linker error mentioning `RepoPromptHeadlessServer`). Report
  the exact error. The fallback — extracting `HeadlessToolSchemas.swift`
  into a small `RepoPromptHeadlessCore` library target (it imports only
  `MCP`, verified) — is pre-approved as the alternative, but report before
  doing it so the reviewer can confirm.
- `MCP.Value` is not `Encodable`, making Step 3's JSON round-trip
  impossible (highly unlikely — it is serialized into `tools/list`
  responses — but if so, report rather than reaching for reflection).
- Declaring `required: ["op"]` makes `mcp_agent_smoke.py` fail (an MCP SDK
  that enforces schemas server-side would change runtime behavior — the
  smoke never omits `op`, so this is unexpected; report it).

## Maintenance notes

- Future schema additions (e.g. plan 008's `cancelling`, a future `steer`
  op) should extend these tests — they now fail honestly on drift.
- If the test suite ever needs to run on Linux, the `@testable import` of an
  executable target with top-level code may need the library-extraction
  fallback after all; note it in the index if that happens.
- Reviewer focus: the exact-count assertion (11) — it's the tripwire for
  silent tool additions; bump it deliberately when adding tools.
