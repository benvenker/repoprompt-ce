# Plan 004: Make `RepoPromptContextCore` + `rpce-headless` build and run on Linux

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: confirm plans 002 and 003 are DONE in
> `plans/README.md`, and `swift build --product rpce-headless` exits 0 on
> macOS before you change anything.

## Status

- **Current**: DONE — plan 001 passed on the Ubuntu 24.04 VPS using
  `swift:6.2.4-noble`; plan 004 now also builds and smokes `rpce-headless`
  in that image on the same VPS.
- **Priority**: P1
- **Effort**: M
- **Risk**: MED (platform conditionals; bounded by the verified inventory below)
- **Depends on**: plans/002, plans/003; plan 001's recorded image tag/results
- **Category**: migration
- **Planned at**: commit `1db9bbc`, 2026-06-11
- **Status**: DONE

## Why this matters

The whole point of this fork is running the context engine on a Linux VPS.
Plans 002–003 produce a macOS-only headless server. A pre-planning scan found
the Linux-blocking surface is small and enumerable: one FSEvents/CoreServices
usage, four CryptoKit files, five Darwin-import files, and shallow Combine
usage. This plan applies those mechanical substitutions and proves the result
in Docker using the image recorded by plan 001.

## Current state

Scanned at `1db9bbc` (paths below are pre-002-move; after the move they live
under `Sources/RepoPromptContextCore/` — locate with the greps given):

- **FSEvents/CoreServices — exactly one file**: `WorkspaceFileContextStore.swift`
  imports `CoreServices` (line 2) and uses `FSEventStreamEventFlags`/
  `FSEventStreamEventId` in a callback signature (line 536 region). This is
  the live file-watching path.
- **CryptoKit — four files** (all hashing): `Sources/RepoPromptShared/MCP/JSONRPCBridgeLedger.swift`,
  `WorkspaceContext/Slices/SliceRebaseEngine.swift`,
  `WorkspaceContext/Slices/PartitionStore.swift`, `CodeMap/CodeMapCacheManager.swift`.
  `swift-crypto`'s `Crypto` module is API-compatible for SHA-256 etc.
- **Darwin imports — five files**, all socket/fd plumbing:
  `Sources/RepoPromptShared/MCP/POSIXDescriptorSupport.swift`,
  `Sources/RepoPromptShared/MCP/MCPFilesystemIdentity.swift`,
  `Sources/RepoPromptMCP/Transports/BootstrapSocketMCPTransport.swift`,
  `Sources/RepoPromptMCP/Shared/NewlineDelimitedSocketReader.swift`,
  `Sources/RepoPromptMCP/Transports/NonBlockingFDWriter.swift`.
  Only the first two matter for `rpce-headless` (the `RepoPromptMCP` proxy
  target is NOT being ported; fix its files only if they block the build of
  targets you care about — `RepoPromptShared` IS linked by both).
- **Combine** — `import Combine` appears in `TokenCalculationService.swift`
  (zero Combine symbols — vestigial) and `WorkspaceFileContextStore.swift`
  (grep hits are mostly domain naming like "publisherIngress", not Combine
  types — verify with
  `grep -n "Published\|CurrentValueSubject\|PassthroughSubject\|AnyCancellable\|AnyPublisher" <file>`).
  Combine does not exist on Linux; whatever real usage exists must be
  replaced (AsyncStream or plain callbacks) or `#if canImport(Combine)`-gated
  if it's macOS-only convenience.
- **`platforms: [.macOS(.v14)]`** at `Package.swift:6` only sets Apple
  minimums — no change needed for Linux.
- **DispatchSource/libdispatch** ships with Swift on Linux — usages are fine.
- Plan 001's Results section records the working Swift Docker image tag and
  whether SwiftTreeSitter/CSwiftPCRE2 passed. **Read it first.** If 001 was
  BLOCKED, this plan inherits the block.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| macOS regression | `swift build --product rpce-headless && swift build --product RepoPrompt` | exit 0 |
| Linux build | `docker run --rm -v "$PWD":/src -w /src <IMAGE> swift build --product rpce-headless --scratch-path .build-linux` | exit 0 |
| Linux smoke | `docker run --rm -v "$PWD":/src -w /src <IMAGE> bash -c "swift build --product rpce-headless --scratch-path .build-linux && python3 Sources/RepoPromptHeadlessServer/Scripts/mcp_smoke.py .build-linux/debug/rpce-headless /src"` | `ALL OK` |
| macOS tests | `swift test --filter WorkspaceFileContextStoreTests` | pass |

`<IMAGE>` = the tag recorded in plan 001 Results (`swift:6.2.4-noble`). If
the image lacks `python3`, install once in the run
(`apt-get update && apt-get install -y python3`) or bake a tiny derived image.

## Scope

**In scope**:
- `Package.swift` (add `swift-crypto` dependency, conditionalize if needed)
- `Sources/RepoPromptContextCore/**` (platform conditionals only)
- `Sources/RepoPromptShared/**` (platform conditionals only)
- `Sources/RepoPromptHeadlessServer/**`
- `.gitignore` (add `.build-linux/`)
- `plans/README.md`

**Out of scope** (do NOT touch):
- `Sources/RepoPrompt/**` (the Mac app — it never builds on Linux and doesn't need to)
- `Sources/RepoPromptMCP/**` unless a `RepoPromptShared` change forces a
  matching guard (keep such edits to `#if canImport(Darwin)` wrappers)
- Behavior changes on macOS — every substitution must keep the macOS path
  identical (`#if` around the old code, not deletion)

## Git workflow

- Branch: `headless/004-linux`
- Commit per step. Same preflight note as plan 002.

## Steps

### Step 1: Read plan 001 results; set up the Linux loop

Record `<IMAGE>`. Add `.build-linux/` to `.gitignore`. Run the Linux build
command once to get the initial error inventory; save it to
`/tmp/linux-errors-baseline.txt`. Don't fix anything yet.

**Verify**: the error list exists; macOS builds still pass untouched.

### Step 2: CryptoKit → swift-crypto

1. `Package.swift`: add `.package(url: "https://github.com/apple/swift-crypto.git", from: "4.0.0")`
   and add `.product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux]))`
   to `RepoPromptContextCore` and `RepoPromptShared`... **note**:
   `RepoPromptShared` currently has zero deps (`Package.swift:94` —
   `.target(name: "RepoPromptShared", path: "Sources/RepoPromptShared")`);
   give it the conditional Crypto product dependency.
2. In each of the four CryptoKit files, replace `import CryptoKit` with:
   ```swift
   #if canImport(CryptoKit)
   import CryptoKit
   #else
   import Crypto
   #endif
   ```
   No other change — the SHA-256/Insecure APIs are source-compatible. If a
   used API is missing from swift-crypto, STOP with the symbol name.

**Verify**: macOS builds pass; Linux error baseline shrinks (re-run, diff).

### Step 3: Darwin → Glibc guards

In `POSIXDescriptorSupport.swift` and `MCPFilesystemIdentity.swift` (and any
other file the Linux build flags inside Shared/ContextCore/HeadlessServer):

```swift
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
```

Constant/API differences to expect and their standard fixes: `O_NONBLOCK`
etc. exist in Glibc; `Darwin.POSIX.fcntl`-style qualified imports become
plain `Glibc`; `errno` access is the same. Fix only what the compiler flags.

**Verify**: macOS builds pass; Linux baseline shrinks.

### Step 4: File watching seam (FSEvents)

In the store (now `Sources/RepoPromptContextCore/WorkspaceContext/WorkspaceFileContextStore.swift`):

1. Wrap the FSEvents-specific code (the `import CoreServices`, the event
   callback machinery around the old line 536, and the watcher start/stop)
   in `#if os(macOS) ... #endif`.
2. For Linux, add the minimal honest substitute: **no live watching**.
   Provide `func rescan() async` (or reuse the store's existing
   refresh/ingress entry — find it via
   `grep -n "func.*rescan\|func.*refresh\|reload" Sources/RepoPromptContextCore/WorkspaceContext/WorkspaceFileContextStore.swift`)
   and have `rpce-headless` call it (a) on `serve` startup (already happens)
   and (b) when a `tools/call` arrives more than N seconds (default 5) after
   the previous one — implement that debounce in `HeadlessWorkspaceHost`.
   This keeps results fresh enough for agent workloads without inotify.
3. Leave a `// LINUX-TODO: inotify watcher` marker comment at the seam.

**Verify**: macOS builds + `swift test --filter WorkspaceFileContextStoreTests`
pass (macOS watching untouched); Linux baseline shrinks.

### Step 5: Combine removal/gating

Run the symbol grep from Current state on both files. Vestigial imports →
delete the `import Combine` line. Real-but-shallow usage → replace with
`AsyncStream`/callback equivalents **only if** the Linux build demands it and
the change is local; if a replacement would ripple beyond ~3 files, STOP and
report the usage graph instead.

**Verify**: macOS builds + focused tests pass; Linux baseline shrinks.

### Step 6: Finish the Linux build + smoke

Iterate remaining Linux errors with the smallest possible guards. Expected
stragglers: `String(contentsOf:)` deprecations, `FoundationNetworking`
imports (should NOT appear — no URLSession in these targets; if one appears,
note which file and gate it), case-sensitivity path bugs (Linux FS is
case-sensitive — fix the reference, not the filename).

Then run the Linux smoke command (table above).

**Verify**: `ALL OK` from the harness inside Docker.

### Step 7: Record the recipe

Append a "Linux build" section to `Sources/RepoPromptHeadlessServer/README.md`
with the exact image tag, build command, and smoke command.

## Test plan

- macOS: existing suite via the focused filters (regression only).
- Linux: the Step 6 smoke run **is** the acceptance test. Optionally also run
  `swift test --filter WorkspaceFileContextStoreTests --scratch-path .build-linux`
  in Docker; record pass/fail in README status note (some tests may assume
  macOS paths — failures there are findings to list, not blockers, as long
  as the smoke passes).

## Done criteria

- [x] Linux Docker build of `rpce-headless` exits 0
- [x] Linux Docker smoke prints `ALL OK`
- [x] macOS: `swift build --product RepoPrompt` and `--product rpce-headless` exit 0
- [x] macOS: `swift test --filter WorkspaceFileContextStoreTests` passes
- [x] `grep -rn "import CoreServices" Sources/RepoPromptContextCore/` shows the import only inside platform guards
- [x] `plans/README.md` updated (include the image tag used)

## Results

Validated on 2026-06-11 against the user's Ubuntu 24.04 VPS via Docker:

```bash
docker run --rm -v /tmp/repoprompt-ce-fable:/src -w /src swift:6.2.4-noble \
  swift build --product rpce-headless --scratch-path .build-linux
```

Result: `Build of product 'rpce-headless' complete!`

```bash
docker run --rm -v /tmp/repoprompt-ce-fable:/src -w /src swift:6.2.4-noble \
  bash -lc 'apt-get update && apt-get install -y python3 && \
  python3 Sources/RepoPromptHeadlessServer/Scripts/mcp_smoke.py \
  .build-linux/debug/rpce-headless /src'
```

Result: `INIT OK` followed by `ALL OK`.

The final package resolution keeps `swift-crypto` on the existing 4.x line
(`4.5.0` during validation) instead of downgrading the lockfile to 3.x.
Additional macOS regression validation:

```bash
swift build --product rpce-headless
make dev-swift-build PRODUCT=RepoPrompt
make dev-test FILTER=WorkspaceFileContextStoreTests
```

Results: both builds exited 0; the focused test ran 112 tests with 0 failures.

## STOP conditions

- Plan 001 Results show FAIL for SwiftTreeSitter or CSwiftPCRE2 (inherited block).
- A swift-crypto API gap (name the symbol).
- Combine usage in the store turns out to be load-bearing and non-local (>3 files to change).
- Store population on Linux returns zero files for a non-empty root after one
  debugging attempt (suspect: case-sensitivity or path-resolution assumptions
  — capture findings and report).

## Maintenance notes

- The Linux file-freshness model is rescan-on-demand with debounce; if the
  VPS workload needs push freshness, a future inotify watcher slots in at the
  `LINUX-TODO` seam.
- Keep new code in ContextCore platform-clean: Darwin-only API belongs behind
  `#if canImport(Darwin)` from day one.
- Deferred: CI workflow for the Linux build (one `docker run` in CI when wanted).
