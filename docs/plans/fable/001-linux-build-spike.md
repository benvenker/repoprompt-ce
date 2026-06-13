# Plan 001: Prove the parsing stack (tree-sitter + PCRE2) builds and runs on Linux

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` and fill in the "Results" section at the bottom of
> this file.
>
> **Drift check (run first)**: `git diff --stat 1db9bbc..HEAD -- Package.swift Sources/CSwiftPCRE2 Sources/RepoPromptC Sources/TreeSitterScannerSupport`
> If any of those changed since this plan was written, compare the "Current
> state" excerpts below against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW (no repo changes at all)
- **Depends on**: none
- **Category**: migration (de-risking spike)
- **Planned at**: commit `1db9bbc`, 2026-06-11

## Why this matters

The whole headless-Linux extraction (plans 002–006) rests on one unproven
assumption: that the repo's parsing stack — `SwiftTreeSitter` 0.8.0, the
pinned tree-sitter grammar packages, and the vendored `CSwiftPCRE2` C target —
compiles and runs under Swift on Linux. Everything else we scanned is plain
Foundation. If this assumption is false we need to know **before** any
Package.swift surgery, because the fix (vendoring different bindings, or
regenerating the PCRE2 `config.h` for Linux) changes plan 002's shape. This
spike costs an hour and produces a yes/no answer plus exact error output.

This spike makes **zero changes to the repository**. All work happens in
`/tmp/rpce-linux-spike` and inside a Docker container.

## Current state

- `Package.swift:1` — `// swift-tools-version: 6.2`; `Package.swift:6` —
  `platforms: [.macOS(.v14)]` (this only sets the *Apple* minimum; it does
  not block Linux builds).
- `Package.swift:20` — `.package(url: "https://github.com/ChimeHQ/SwiftTreeSitter.git", exact: "0.8.0")`.
- Grammar packages are pinned by revision at `Package.swift:21-33`. The three
  you will use in the spike:
  - tree-sitter-swift: `revision: "9253825dd2570430b53fa128cbb40cb62498e75d"` (`Package.swift:30`)
  - tree-sitter-python: `revision: "c5fca1a186e8e528115196178c28eefa8d86b0b0"` (`Package.swift:26`)
  - tree-sitter-typescript: `revision: "75b3874edb2dc714fb1fd77a32013d0f8699989f"` (`Package.swift:28`)
- `Package.swift:95` — the `CSwiftPCRE2` target definition. It is a vendored
  PCRE2 with a long `exclude:` list (sljit allocator/JIT files) and
  `cSettings` defining `PCRE2_CODE_UNIT_WIDTH=8` and `HAVE_CONFIG_H`. The
  vendored `config.h` may have been generated on macOS — **that is one of the
  two things this spike exists to test.**
- How the app actually calls tree-sitter (mirror this in your spike code):
  `Sources/RepoPrompt/Infrastructure/SyntaxParsing/SyntaxManager.swift:8-20`
  imports `SwiftTreeSitter` plus `TreeSitterSwift`, `TreeSitterPython`,
  `TreeSitterTypeScript` (and others); parsing setup is around
  `SyntaxManager.swift:325-341` (language → `tree_sitter_*` function mapping)
  and `SyntaxManager.swift:432-444` (`Parser` / `setLanguage` usage). Read
  those regions before writing the spike's `main.swift`.
- How the app calls PCRE2 (mirror this too):
  `Sources/RepoPrompt/Infrastructure/Regex/PCRE2RegexAdapter.swift` — the
  compile entry point is `RepoPromptPCRE2Adapter.compile` near line 76.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Docker present | `docker info` | exit 0 (OrbStack/Colima fine) |
| Pull image | `docker pull swift:6.2` | image pulled (fallback: `swift:6.1`, see Step 4) |
| macOS sanity build | `cd /tmp/rpce-linux-spike && swift build` | exit 0 |
| Linux build+run | see Step 4 | prints `TREESITTER_OK` and `PCRE2_OK` |

## Scope

**In scope** (the only places you create/modify files):
- `/tmp/rpce-linux-spike/` (throwaway SwiftPM package)
- `plans/001-linux-build-spike.md` (the Results section below)
- `plans/README.md` (your status row)

**Out of scope** (do NOT touch):
- Every file in the repository outside `plans/`. This spike changes nothing
  in the repo. You may **read** repo files freely (and must, for the API
  usage patterns above), and you may **copy** `Sources/CSwiftPCRE2` out to
  the spike directory.

## Git workflow

No repo branch needed — the only repo edits are the two `plans/` files,
which you may commit directly on a branch named `headless/001-linux-spike`
with a message like `Record Linux parsing-stack spike results`.

## Steps

### Step 1: Scaffold the spike package

Create `/tmp/rpce-linux-spike/Package.swift`:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "rpce-linux-spike",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/ChimeHQ/SwiftTreeSitter.git", exact: "0.8.0"),
        .package(url: "https://github.com/alex-pinkus/tree-sitter-swift", revision: "9253825dd2570430b53fa128cbb40cb62498e75d"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-python", revision: "c5fca1a186e8e528115196178c28eefa8d86b0b0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-typescript", revision: "75b3874edb2dc714fb1fd77a32013d0f8699989f"),
    ],
    targets: [
        .executableTarget(
            name: "spike",
            dependencies: [
                "CSwiftPCRE2",
                .product(name: "SwiftTreeSitter", package: "SwiftTreeSitter"),
                .product(name: "TreeSitterSwift", package: "tree-sitter-swift"),
                .product(name: "TreeSitterPython", package: "tree-sitter-python"),
                .product(name: "TreeSitterTypeScript", package: "tree-sitter-typescript"),
            ]
        ),
        // CSwiftPCRE2 target stanza: copy it VERBATIM from the repo's
        // Package.swift line 95 (the whole `.target(name: "CSwiftPCRE2", ...)`
        // entry, including the full exclude list and cSettings).
    ]
)
```

Then copy the vendored C sources:

```bash
mkdir -p /tmp/rpce-linux-spike/Sources
cp -R /Users/ben/code/repoprompt-ce/Sources/CSwiftPCRE2 /tmp/rpce-linux-spike/Sources/
mkdir -p /tmp/rpce-linux-spike/Sources/spike
```

**Verify**: `ls /tmp/rpce-linux-spike/Sources/CSwiftPCRE2/include` → shows headers (e.g. `path_search.h` is NOT here — that's RepoPromptC; you should see PCRE2-related headers).

### Step 2: Write the spike program

Create `/tmp/rpce-linux-spike/Sources/spike/main.swift`. Before writing it,
read these repo files for the exact current API shapes:

- `Sources/RepoPrompt/Infrastructure/SyntaxParsing/SyntaxManager.swift` lines 320–450
- `Sources/RepoPrompt/Infrastructure/Regex/PCRE2RegexAdapter.swift` (whole file)

The program must:

1. Construct a tree-sitter `Parser`, set the Swift language (mirroring
   `SyntaxManager`'s `Parser`/`setLanguage` calls), parse the string
   `"func hello() -> Int { return 1 }"`, and print `TREESITTER_OK <node count or s-expression>`
   if a non-nil root node is produced. Repeat for Python and TypeScript with
   one-line snippets.
2. Compile the regex `fu?nc\s+(\w+)` through the same PCRE2 C calls that
   `PCRE2RegexAdapter` uses (you may transliterate its compile+match path),
   match it against the same string, and print `PCRE2_OK <captured name>`
   on success (expected capture: `hello`).

**Verify (macOS first)**: `cd /tmp/rpce-linux-spike && swift build && swift run spike` → exit 0, output contains `TREESITTER_OK` (×3 languages) and `PCRE2_OK hello`.
If the macOS build fails, fix the spike code (API misuse) — do not proceed to
Linux until macOS passes, since macOS failures are spike bugs, not platform findings.

### Step 3: Linux build + run in Docker

```bash
docker run --rm -v /tmp/rpce-linux-spike:/src -w /src swift:6.2 \
  bash -c "swift build --scratch-path .build-linux && swift run --scratch-path .build-linux spike"
```

If the `swift:6.2` image does not exist, use `swift:6.1` AND change the
spike's `// swift-tools-version:` to 6.1 (record that in Results).

**Verify**: exit 0; output contains all `TREESITTER_OK` lines and `PCRE2_OK hello`.

### Step 4: Record results

Fill in the **Results** section below with: pass/fail per component
(SwiftTreeSitter, each grammar, CSwiftPCRE2), the Swift image tag used, and —
on any failure — the first 30 lines of compiler/linker error output verbatim.
Update `plans/README.md` status to DONE (or BLOCKED with one line).

## Test plan

The spike program IS the test. No repo tests are touched.

## Done criteria

- [ ] macOS: `swift run spike` prints `TREESITTER_OK` ×3 and `PCRE2_OK hello`
- [ ] Linux (Docker): same output, exit 0
- [ ] Results section below filled in
- [ ] `git status` in the repo shows changes only under `plans/`
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- `SwiftTreeSitter` 0.8.0 fails to **compile** on Linux with errors that are
  not obviously missing-`import Foundation` trivia. Capture the errors. (The
  fallback decision — pin a newer SwiftTreeSitter, or switch to the official
  `tree-sitter/swift-tree-sitter` successor — belongs to the human, because
  plan 002 pins whatever you validate here.)
- `CSwiftPCRE2` fails on Linux due to `config.h` / `HAVE_CONFIG_H` problems.
  Capture errors; regenerating PCRE2 config for Linux is its own task.
- Docker is unavailable and cannot be started. (No Docker → no spike.)

## Maintenance notes

- Whatever image tag and revisions pass here become the pinned toolchain for
  plan 004's Docker verification — record them precisely.
- The spike directory is throwaway; delete it after recording results.

## Results

DONE on 2026-06-11. Docker Desktop on the Mac had trouble pulling the large
Ubuntu Swift compiler layers, but the target VPS (`ssh netcup`) is Ubuntu
24.04.4 LTS (`noble`) on `amd64` and successfully pulled/runs
`swift:6.2.4-noble`. The throwaway spike package was synced to the VPS and
run inside that container.

- Swift image used: `swift:6.2.4-noble`
- Swift version: `Swift version 6.2.4 (swift-6.2.4-RELEASE)`,
  target `x86_64-unknown-linux-gnu`
- macOS spike: PASS (`TREESITTER_OK` for Swift/Python/TypeScript and
  `PCRE2_OK hello`)
- SwiftTreeSitter on Linux: PASS
- Grammars (swift/python/typescript): PASS
- CSwiftPCRE2 on Linux: PASS
- Error excerpts (if any): none for the final Linux run

```text
Linux spike output:
TREESITTER_OK Swift source_file
TREESITTER_OK Python module
TREESITTER_OK TypeScript program
PCRE2_OK hello
```
