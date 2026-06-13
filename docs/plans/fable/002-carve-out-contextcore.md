# Plan 002: Carve the deterministic context engine into a `RepoPromptContextCore` library target

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 1db9bbc..HEAD -- Package.swift Sources/RepoPrompt/Infrastructure/WorkspaceContext Sources/RepoPrompt/Features/CodeMap Sources/RepoPrompt/Features/Search Sources/RepoPrompt/Infrastructure/SyntaxParsing Sources/RepoPrompt/Infrastructure/Regex Sources/RepoPrompt/Features/Prompt/Services`
> If files changed since `1db9bbc`, compare the "Current state" excerpts
> against the live code before proceeding; on a mismatch, STOP.

## Status

## Implementation status (2026-06-11)

- **Status**: DONE per user-directed no-commit workflow; changes are intentionally left unstaged.
- **Validation**:
  - `make dev-swift-build PRODUCT=RepoPrompt` passed (ticket `3f31ddc0-72b3-425c-9348-415d9922bb10`).
  - `make dev-swift-build PRODUCT=repoprompt-mcp` passed (ticket `c9321f42-5993-483d-8865-20f4fd4ed68c`).
  - `make dev-test FILTER=WorkspaceFileContextStoreTests` passed (112 tests, ticket `cd4b1812-1d3b-4cca-950e-ae476b65d902`).
  - `make dev-test FILTER=CodexIntegrationConfigurationTests` passed (16 tests, ticket `63aed8f4-5f41-4fed-9243-87b354486993`).
  - `make dev-test FILTER=CodeMap` passed (6 tests, ticket `10e3cf16-ef10-46ad-856c-10b3faf1abbe`).
  - `grep -rnE "^import (SwiftUI|AppKit|Neon)" Sources/RepoPromptContextCore` returned no matches.
- **Not run**: full `swift test`/`make dev-test` was not run; plan allows the two named filters as the minimum when the full suite is impractical.
- **Formatter**: `make dev-format` was attempted but failed because `swiftformat` is not installed (`Missing required tool: swiftformat`); no install/escalation was performed.
- **Leave-behinds/splits**:
  - `Sources/RepoPrompt/Features/Workspaces/Selection/WorkspaceSelectionCoordinator.swift` remains app-side for `WorkspaceManagerViewModel`.
  - `Sources/RepoPrompt/Infrastructure/SyntaxParsingApp/ComprehensiveHiglighter.swift` remains app-side for `AppKit`/`Neon`.
  - `Sources/RepoPrompt/Features/CodeMapApp/CodeMapExtractorLegacy.swift` and `CodeMapExtractorSnapshotsApp.swift` keep `FolderViewModel`/`FileViewModel` adapters app-side.
  - `Sources/RepoPrompt/Features/SearchApp/FileSearchActor+FileViewModel.swift`, `Sources/RepoPrompt/Features/WorkspaceFiles/Models/PathMatchingAppAdapters.swift`, and `Sources/RepoPrompt/Features/Prompt/Services/PromptPackagingServiceApp.swift` keep app-specific adapters out of `RepoPromptContextCore`.

- **Priority**: P1
- **Effort**: L
- **Risk**: MED (large mechanical move; mitigated by per-step build gates)
- **Depends on**: none strictly; plan 001's PASS result is strongly recommended first
- **Category**: tech-debt / migration
- **Planned at**: commit `1db9bbc`, 2026-06-11

## Why this matters

RepoPrompt CE's context engine (file selection store, codemaps, search, token
accounting, prompt packaging) currently lives inside the **app executable
target** `RepoPrompt`, so nothing else can link it. The goal of this fork is
a headless Linux MCP server (plan 003) that reuses this engine. SwiftPM
cannot link one executable target into another, so the engine must move into
a library target. This plan is pure target surgery: after it lands, the app
builds and behaves exactly as before, but ~30 KLOC of deterministic engine
code lives in a new `RepoPromptContextCore` library that a server target can
depend on.

This is a **private fork**: upstream mergeability does not matter. Prefer
simple over clever. The macOS app must still build (it's our regression net),
but you may freely add `public` modifiers, move files, and split files.

## Current state

- Products (`Package.swift:7-9`): executables `RepoPrompt` (the app) and
  `repoprompt-mcp` (a thin proxy CLI). No library targets except
  `RepoPromptShared` (protocol DTOs only, `Package.swift:94`).
- The app target stanza (`Package.swift:43-87`) owns every heavyweight dep:
  `"RepoPromptC", "CSwiftPCRE2", "TreeSitterScannerSupport"` (line 47),
  `SwiftTreeSitter` + 13 grammar products (lines 55–68), `Neon`,
  `UniversalCharsetDetection`/`Cuchardet` (lines 72–73), `JSONSchema`,
  `Ontology`, providers. It also compiles with a bridging header
  (`Package.swift:82-85`) — that header is anti-debug hardening
  (ptrace/sysctl) and is NOT needed by any of the directories you are moving.
- The proxy target stanza, for reference (`Package.swift:88-93`):

  ```swift
  .executableTarget(
      name: "RepoPromptMCP",
      dependencies: ["RepoPromptShared", .product(name: "Logging", package: "swift-log"), .product(name: "MCP", package: "swift-sdk"), .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"), .product(name: "SystemPackage", package: "swift-system")],
      path: "Sources/RepoPromptMCP",
      swiftSettings: [.define("DEBUG", .when(configuration: .debug))]
  ),
  ```

- The test target is declared at `Package.swift:101` (`Tests/RepoPromptTests`).

**Move inventory** (verified directory listings at `1db9bbc`):

| Directory | Contents | Known app-type couplings |
|---|---|---|
| `Sources/RepoPrompt/Infrastructure/WorkspaceContext/` | subdirs `Indexing, Models, PathLookup, PathResolution, Search, Selection, Slices, TokenAccounting` + `WorkspaceFileContextStore.swift`, `WorkspaceFileMutationService.swift`, `WorkspaceFileSystemIngressCoordinator.swift`, `WorkspaceGitDiffSelectionResolver.swift`, `WorkspaceReadableFileService.swift`, `WorkspaceRootBindingProjection.swift`, `WorkspaceSearchDecodedContentCache.swift` | `Selection/WorkspaceSelectionCoordinator.swift` is `@MainActor` and references `WorkspaceManagerViewModel` — it stays app-side (Step 3) |
| `Sources/RepoPrompt/Infrastructure/Regex/` | `PCRE2RegexAdapter.swift`, `RegexToolkit.swift` | none known |
| `Sources/RepoPrompt/Features/Search/` | `SearchMatch.swift`, `SearchPathFiltering.swift`, `StoreBackedWorkspaceSearch.swift`, `StoreBackedWorkspaceSearchLane.swift` | `StoreBackedWorkspaceSearch` has an optional `WorkspaceManagerViewModel` reference used only for readiness/timing — replace per Step 4 |
| `Sources/RepoPrompt/Infrastructure/SyntaxParsing/` | `SyntaxManager.swift`, `QueryResourceLoader.swift`, `Queries/` (resource dir), `ComprehensiveHiglighter.swift` | `ComprehensiveHiglighter.swift` likely imports `Neon` (UI highlighting) — check imports; if it does, it stays app-side |
| `Sources/RepoPrompt/Features/CodeMap/` | 16 Swift files + `LanguageStrategies/`, `Models/` | `CodeMapExtractor.swift:2` has a **vestigial** `import SwiftUI` (no SwiftUI symbols used — delete the line). Its legacy file-tree context references `FolderViewModel` around lines 21–65 — handle per Step 5 |
| `Sources/RepoPrompt/Features/Prompt/Services/` | `PromptContextAccountingService.swift`, `PromptContextGitDiffPolicy.swift`, `PromptContextPreAssemblyService.swift`, `PromptPackagingService.swift` | designed view-model-free (the accounting service documents this) |
| `Sources/RepoPrompt/Features/Prompt/Models/PromptAssemblyBuilder.swift` | single file | pull further `Prompt/Models/` files only if the compiler demands them |

Token counting really is a dependency-free heuristic — no tokenizer library
exists in this repo. Verified at
`Sources/RepoPrompt/Infrastructure/WorkspaceContext/TokenAccounting/TokenCalculationService.swift:130-132`:

```swift
static func estimateTokens(for text: String) -> Int {
    // (line 132)
    return Int((Double(bytes) / 4.0) * 1.05)
```

Store imports (`WorkspaceFileContextStore.swift:1-4`): `Combine`,
`CoreServices`, `Dispatch`, `Foundation` — all fine on macOS; Linux concerns
are plan 004's job, NOT yours.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Build app | `swift build --product RepoPrompt` | exit 0 |
| Build proxy | `swift build --product repoprompt-mcp` | exit 0 |
| Focused tests | `swift test --filter WorkspaceFileContextStoreTests` | all pass |
| Full tests (final gate) | `swift test` | all pass |
| Lint (optional, end only) | `make lint` | exit 0 |

Coordinated alternatives exist (`make dev-swift-build PRODUCT=RepoPrompt`,
`make dev-test FILTER=...`) — use them if other agents are building in this
checkout; otherwise the direct commands above are fine.

## Scope

**In scope** (modify):
- `Package.swift`
- The directories in the move inventory (moving them under `Sources/RepoPromptContextCore/`)
- New app-side homes for left-behind files (e.g. `Sources/RepoPrompt/Features/Workspaces/Selection/`)
- `public` access-control modifiers and `import RepoPromptContextCore` lines anywhere the compiler demands (app + `Sources/RepoPromptMCP` if needed + `Tests/RepoPromptTests`)
- `plans/README.md` (status)

**Out of scope** (do NOT touch):
- Behavior. No logic changes, no renames of types/functions, no "improvements while you're in there".
- `Sources/RepoPromptShared` (already a separate target; leave it).
- `Sources/RepoPrompt/Features/Prompt/ViewModels/` (PromptViewModel and friends stay app-side).
- The bridging header and its build settings (app-target-only).
- Everything under `docs/`.

## Git workflow

- Branch: `headless/002-contextcore`
- Commit after each numbered step that ends green (subject style: short
  imperative, e.g. `Move WorkspaceContext into RepoPromptContextCore`).
- This repo normally requires `.agents/skills/rpce-contribution-check/scripts/preflight.sh commit`
  before committing. Run it; on this private fork, if it fails on
  contributor-allowlist/identity checks, note that in the commit body and
  proceed. If it reports a **secret finding**, STOP.
- Do not push.

## Steps

### Step 1: Add the empty library target

In `Package.swift`:
1. Add to `products:`: `.library(name: "RepoPromptContextCore", targets: ["RepoPromptContextCore"]),`
2. Add a target:
   ```swift
   .target(
       name: "RepoPromptContextCore",
       dependencies: [
           "RepoPromptC", "CSwiftPCRE2", "TreeSitterScannerSupport",
           .product(name: "Logging", package: "swift-log"),
           .product(name: "SwiftTreeSitter", package: "SwiftTreeSitter"),
           // all 13 TreeSitter* grammar products — copy the .product lines
           // verbatim from the RepoPrompt target (Package.swift:55-68)
           .product(name: "UniversalCharsetDetection", package: "UniversalCharsetDetection"),
           .product(name: "Cuchardet", package: "UniversalCharsetDetection"),
       ],
       path: "Sources/RepoPromptContextCore",
       swiftSettings: [.define("DEBUG", .when(configuration: .debug))]
   ),
   ```
3. Add `"RepoPromptContextCore"` to the `RepoPrompt` app target's dependencies.
   Leave the app's existing dependency lines alone for now (duplicate deps
   between app and lib are fine at this stage).
4. `mkdir -p Sources/RepoPromptContextCore` and add a placeholder
   `Sources/RepoPromptContextCore/Placeholder.swift` containing
   `// RepoPromptContextCore` (SwiftPM requires ≥1 source file).

**Verify**: `swift build --product RepoPrompt` → exit 0.

### Step 2: Move the leaf modules (Regex, Search)

```bash
git mv Sources/RepoPrompt/Infrastructure/Regex Sources/RepoPromptContextCore/Regex
git mv Sources/RepoPrompt/Features/Search Sources/RepoPromptContextCore/Search
```

Build the app. You will now hit two error classes — fix them mechanically:

- **Missing types in app code** (`cannot find type 'X' in scope`): add
  `import RepoPromptContextCore` to the failing app file.
- **Access control** (`'X' is inaccessible due to 'internal' protection level`
  or `initializer is inaccessible`): in the moved file, add `public` to the
  named declaration. Rules for a clean pass:
  - `struct`/`class`/`enum`/`protocol`/`typealias` → `public struct` etc.
  - For structs whose **memberwise init** is used across the boundary, add an
    explicit `public init(...)` assigning every stored property (Swift never
    makes memberwise inits public automatically).
  - Members (funcs, vars, enum nested types) referenced from the app →
    `public`. Enum **cases** inherit the enum's access — no per-case change.
  - Do NOT blanket-publicize whole files; only what the compiler demands.

Iterate `swift build --product RepoPrompt` until green.

**Verify**: both `swift build --product RepoPrompt` and
`swift build --product repoprompt-mcp` → exit 0. Commit.

### Step 3: Move WorkspaceContext (with one leave-behind)

```bash
git mv Sources/RepoPrompt/Infrastructure/WorkspaceContext Sources/RepoPromptContextCore/WorkspaceContext
mkdir -p Sources/RepoPrompt/Features/Workspaces/Selection
git mv Sources/RepoPromptContextCore/WorkspaceContext/Selection/WorkspaceSelectionCoordinator.swift Sources/RepoPrompt/Features/Workspaces/Selection/
```

`WorkspaceSelectionCoordinator.swift` stays app-side because it is a
`@MainActor` adapter onto `WorkspaceManagerViewModel` (an app view model).
Then run the same two-error-class fix loop as Step 2. Expect this to be the
largest publicizing pass (the store and its DTOs are widely referenced).

If any OTHER moved file fails to compile because it references an app type
(`*ViewModel`, `WindowState`, SwiftUI views), move that single file back to a
new app-side directory `Sources/RepoPrompt/Infrastructure/WorkspaceContextApp/`
(keeping its subpath) and record it in the README status note. More than
**3** such surprise leave-behinds → STOP (the inventory was wrong).

**Verify**: both products build; `swift test --filter WorkspaceFileContextStoreTests`
→ all pass (you will likely need `@testable import RepoPromptContextCore`
added next to `@testable import RepoPrompt` in failing test files, and
`"RepoPromptContextCore"` added to the testTarget dependencies at
`Package.swift:101`). Commit.

### Step 4: Move SyntaxParsing + CodeMap

1. Check `head -12 Sources/RepoPrompt/Infrastructure/SyntaxParsing/ComprehensiveHiglighter.swift`.
   If it imports `Neon`, `SwiftUI`, or `AppKit`, leave it app-side (move it to
   `Sources/RepoPrompt/Infrastructure/SyntaxParsingApp/`); otherwise move it
   with the rest.
2. ```bash
   git mv Sources/RepoPrompt/Infrastructure/SyntaxParsing Sources/RepoPromptContextCore/SyntaxParsing
   git mv Sources/RepoPrompt/Features/CodeMap Sources/RepoPromptContextCore/CodeMap
   ```
3. `Queries/` is a **resource directory**. Check how the app target declared
   it: `grep -n "Queries\|resources" Package.swift`. Ensure the new target
   declares it, e.g. add to the `RepoPromptContextCore` target:
   `resources: [.copy("SyntaxParsing/Queries")]` (match whatever rule the app
   target used; if the app used `.process`, keep `.process`). Then check
   `QueryResourceLoader.swift` for `Bundle` usage — `Bundle.module` resolves
   per-target, so after the move it points at the new target's bundle, which
   is correct. If it references the app bundle by name/identifier, STOP.
4. Delete the vestigial line `import SwiftUI` at `CodeMapExtractor.swift:2`.
5. `CodeMapExtractor.swift` contains a legacy file-tree context referencing
   `FolderViewModel` (around lines 21–65 at planning time). If the build
   fails on `FolderViewModel`/`FileViewModel`:
   - Split the file: move the legacy declarations (the
     `FileTreeSelectionContext`-related struct(s)/funcs that mention
     `FolderViewModel`) into a new app-side file
     `Sources/RepoPrompt/Features/CodeMapApp/CodeMapExtractorLegacy.swift`,
     declared as `extension CodeMapExtractor { ... }` if they were members.
   - The snapshot-based rendering in `CodeMapExtractor+Snapshots.swift` is
     store-backed and moves cleanly — plan 003 uses only that path.
6. Run the fix loop; build both products.

**Verify**: both products build; `swift test --filter CodeMap` → all
discovered CodeMap tests pass (if the filter matches nothing, run
`swift test --filter WorkspaceFileContextStoreTests` again instead). Commit.

### Step 5: Move the Prompt services

```bash
mkdir -p Sources/RepoPromptContextCore/PromptServices
git mv Sources/RepoPrompt/Features/Prompt/Services/PromptContextAccountingService.swift Sources/RepoPromptContextCore/PromptServices/
git mv Sources/RepoPrompt/Features/Prompt/Services/PromptContextGitDiffPolicy.swift Sources/RepoPromptContextCore/PromptServices/
git mv Sources/RepoPrompt/Features/Prompt/Services/PromptContextPreAssemblyService.swift Sources/RepoPromptContextCore/PromptServices/
git mv Sources/RepoPrompt/Features/Prompt/Services/PromptPackagingService.swift Sources/RepoPromptContextCore/PromptServices/
git mv Sources/RepoPrompt/Features/Prompt/Models/PromptAssemblyBuilder.swift Sources/RepoPromptContextCore/PromptServices/
```

If one of these five references an app view model and won't compile in the
library, move that one back and note it. If the compiler instead asks for
additional small `Prompt/Models/` value types (e.g. `PromptFileEntry.swift`),
move those into `PromptServices/` too — value types only, never `ViewModels/`.

**Verify**: both products build. Commit.

### Step 6: Final gate

1. `swift build --product RepoPrompt` → exit 0
2. `swift build --product repoprompt-mcp` → exit 0
3. `swift test` (full suite) → all pass. If the full suite is impractically
   slow, run at minimum: `swift test --filter WorkspaceFileContextStoreTests`
   and `swift test --filter CodexIntegrationConfigurationTests`, and record
   in the README note that the full suite was not run.
4. `grep -rn "import SwiftUI\|import AppKit" Sources/RepoPromptContextCore/`
   → **no matches**.
5. Launch sanity (optional but recommended if you can run GUI apps):
   `make build` → exit 0 (packages the .app).

## Test plan

No new tests — the existing suite is the characterization net. The grep in
Done criteria is the structural assertion that the library is UI-free.

## Done criteria

- [ ] `swift build --product RepoPrompt` exits 0
- [ ] `swift build --product repoprompt-mcp` exits 0
- [ ] `swift test` exits 0 (or the two named filters pass, recorded in README)
- [ ] `grep -rn "import SwiftUI\|import AppKit" Sources/RepoPromptContextCore/` → no matches
- [ ] `Sources/RepoPromptContextCore` contains the WorkspaceContext, Regex, Search, SyntaxParsing, CodeMap, PromptServices trees
- [ ] `git status` clean after final commit; only in-scope paths changed
- [ ] `plans/README.md` status row updated (note any leave-behind files)

## STOP conditions

Stop and report back (do not improvise) if:

- More than 3 unexpected files (beyond `WorkspaceSelectionCoordinator.swift`
  and possibly `ComprehensiveHiglighter.swift` / the CodeMapExtractor legacy
  split) must be left behind for app-type references.
- A genuine dependency **cycle** appears: a moved file needs an app type that
  itself needs moved types, and the file-split recipe in Step 4.5 doesn't
  apply cleanly.
- `Queries/` resource loading can't be satisfied with `Bundle.module`.
- The full test suite has failures that exist on a clean checkout of
  `1db9bbc` too — record them as pre-existing and continue; failures that are
  NEW after your moves and survive one fix attempt → STOP.

## Maintenance notes

- After this lands, app code and library code live in different modules;
  future app features touching the store/codemaps need `import RepoPromptContextCore`.
- Reviewer focus: the `public` additions (should be minimal-surface, no
  behavior edits) and the CodeMapExtractor split.
- Deferred deliberately: removing now-unused dependency lines from the app
  target (harmless duplication); plan 004 does the platform work.
