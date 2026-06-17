# Agent Notes

RepoPrompt CE is a Swift Package macOS app with three agent-facing surfaces:

- The app and debug MCP CLI, built through `make dev-*` and `./conductor`.
- `rpce-headless`, a standalone MCP server under `Sources/RepoPromptHeadlessServer`.
- Repo-local agent assets under `.agents/skills`, `.smithers`, `.claude`, `.codex`, `.beads`, and `prompt-exports`.

`CLAUDE.md` is a symlink to this file. Keep this file short enough for agents to read before acting.

## First moves

- Check `git status --short` before edits. The tree may already contain intended work; do not revert or clean dirty files unless the user explicitly asks.
- Use Honcho MCP for creating or managing memories.
- For issue-tracker, triage-label, and domain-doc conventions used by engineering skills, read the `## Agent skills` section below.
- Prefer `rg` / `rg --files` for local search.
- Prefer the coordinated daemon for builds, tests, runs, formatting, and release checks. Direct `swift`, `make build`, `make run`, and `make test` are fallback paths.
- Ask for explicit approval immediately before force-push, history rewrite, branch deletion, fork deletion, credential rotation, GitHub-visible destructive mutation, visible app launch/relaunch, or stopping a visible app.

## Agent skills

### Issue tracker

Issues and PRDs are tracked in GitHub Issues for `benvenker/repoprompt-ce`; use the `gh` CLI from this clone. See `docs/agents/issue-tracker.md`.

### Triage labels

Use the canonical triage label vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, and `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

This is a single-context repo: read root `CONTEXT.md` for glossary language and `docs/adr/` for architectural decisions. See `docs/agents/domain.md`.

## Git and preflight

Before every commit or push, read and run the repository-local `$rpce-contribution-check` skill.

```bash
.agents/skills/rpce-contribution-check/scripts/preflight.sh commit
.agents/skills/rpce-contribution-check/scripts/preflight.sh push
```

Commit mode is required after staging and must be rerun after any staging change, including partial staging. Push mode is required after committing and before pushing the current branch.

Versioned hooks live in `.githooks/` and delegate to the same preflight script. Enable them in a clone with:

```bash
git config core.hooksPath .githooks
```

Stage only intended files. Keep local `docs/investigations/*.md` reports unstaged unless the user specifically asks to commit them.

## Coordinated daemon

Use `./conductor` or `make dev-*`. The daemon lane-serializes build, debug artifact, live app, release, and style work so concurrent agents do not stampede `.build` or the running app. It also returns tickets for long jobs.

Common commands:

```bash
make dev-status
make dev-build
make dev-swift-build PRODUCT=RepoPrompt
make dev-swift-build PRODUCT=repoprompt-mcp
make dev-swift-build PRODUCT=rpce-headless
make dev-test
make dev-test FILTER=WorkspaceFileContextStoreTests
make dev-provider-test
make dev-format-check
make dev-lint
make dev-smoke
make dev-smoke-launch
make guardrails
make doctor
```

Use `make dev-format` only when mutating Swift formatting is intended. Use async jobs for long builds:

```bash
./conductor build --async --request-key debug-package
./conductor job wait --request-key debug-package
```

`--request-key` reuses a matching queued or running job. Use `./conductor job status`, `job wait`, `job list`, and `job cancel` to reconnect.

## Running the app

Use `make dev-run` for normal development. For a user-directed newest lifecycle action, use:

```bash
./conductor app relaunch
```

`app relaunch` and `app stop` can cancel older queued or active live-app work. Get explicit approval before using either when it affects the visible app.

Debug signing may auto-detect an Apple Development identity. Without a stable identity, set `ALLOW_ADHOC_SIGNING=1`; ad-hoc debug builds use ephemeral in-memory secure storage. Release packaging requires `SIGN_IDENTITY` and real Keychain storage.

## Debug CLI and live MCP

Use the CE debug CLI for this repo. Production `rp-cli` / `rp-cli-debug` may talk to the non-CE app.

```bash
make debug-cli-status
make install-debug-cli
```

Fallback path when `/usr/local/bin/rpce-cli-debug` is not linked: `"$HOME/Library/Application Support/RepoPrompt CE/repoprompt_ce_cli_debug" -e 'windows'`.

```bash
make dev-smoke
make dev-smoke-launch
```

Enable debug-only Agent Mode diagnostics through `app_settings` only when needed. Confirm `rpce-cli-debug --version` resolves to the current CE debug build before chasing lower-level failures.

## Headless MCP

`rpce-headless` is a standalone MCP server/CLI that does not require the macOS app.

```bash
make dev-swift-build PRODUCT=rpce-headless
.build/debug/rpce-headless serve --root "$PWD"
.build/debug/rpce-headless dump --root "$PWD"
```

For Codex global MCP configuration, prefer launching `rpce-headless serve`
without `--root` so the server loads the chat/workspace current directory.
Hard-coding `--root /data/projects/repoprompt-ce` in global config makes
unrelated repos silently receive the wrong headless workspace.

Agents should discover the loaded headless contract from the tool itself:

```bash
rpce-headless robot-docs status --json
rpce-headless capabilities --json
rpce-headless robot-docs guide
rpce-headless dump --json
```

The full stdio and discovery-restricted socket MCP surfaces expose
`headless_status`; call it first for the compact workspace triage packet:
`loaded_roots`, `loaded_root_metadata`, root mismatch warnings, transport
exposure, suggested first calls, architecture-onboarding steps, and smoke
commands. `headless_capabilities` is the fuller contract with exit codes,
tool exposure, Context Builder examples, agent runner examples, and oracle
guidance. For architecture onboarding, use `context_builder` as the preferred
summarization/filtering path before broad manual reads. Use bounded read-only
server-managed subagents as an optional independent review path: call
`agent_manage list_agents` before `agent_run`, choose an available real
configured agent, inspect logs, and clean up terminal sessions through
`agent_manage`. Do not substitute client-local ad hoc subagents for this
contract. `context_builder` wait calls should stay progress-friendly: use
short `op:"wait"` windows, consume `started_at` / `elapsed_seconds` /
`next_action` snapshots, and expect MCP `notifications/progress` heartbeats
when the client supplies a progress token. Omitted-`op` compatibility calls are
union-shaped: completion inside the sync cap returns the original result shape,
while longer runs return lifecycle snapshots. The default wait cap is
intentional; raise `RPCE_CONTEXT_BUILDER_WAIT_MAX_SECONDS` only when a client
truly wants longer blocking waits. Follow native RepoPrompt workflow shapes for
complex work:
`explore`-style cheap/narrow fact gathering, `context_builder` for curated
selection/synthesis, then `pair` or `design` for the main line or bounded
critique. These native workflow patterns are exposed in `native_workflows` on
`headless_status` and `headless_capabilities`; they are separate from Smithers
workflows. Keep custom workflow plans honest: app-native Agent Mode supports custom markdown
workflows and settings, but headless v1 exposes them as `metadata_only` until a
workflow resolver/settings mutation surface is implemented. Agents may propose
custom workflow markdown and settings changes; do not claim headless
`agent_run workflow_name` works until the resolver exists. Keep
`oracle_send` opt-in/on-demand. When `get_code_structure` has no codemap for a
resolved file, consume its structured `codemap_unavailable` evidence and follow
the `file_search` then `read_file` fallback instead of treating it as a missing
path.

### Linux / VPS Swift

On Linux hosts, especially `ben-netcup-v2`, do not assume Swift is unavailable
just because `swift` is not on `PATH`. This VPS may use Docker Swift instead of
a native host toolchain. Check both before deciding where work must run:

```bash
command -v swift || true
docker images --format '{{.Repository}}:{{.Tag}}' | grep '^swift:' || true
docker run --rm swift:6.2.4-noble swift --version
```

The known-good Linux image for Fable/headless work is `swift:6.2.4-noble`.
Use the existing Docker-built `rpce-headless` binary under `.build-linux` before
trying a new host-side build or smoke path. The host often lacks Swift runtime
libraries even when the Docker build is healthy.

For this Linux machine's Codex MCP binary, use the static artifact installer
instead of copying `.build-linux/debug/rpce-headless` over the host binary:

```bash
make headless-linux-install-local
pkill -TERM -f "rpce-headless serve --root $PWD" || true
```

The installer builds the release artifact in Docker with
`--static-swift-stdlib`, backs up `${RPCE_HEADLESS_INSTALL_BIN:-$HOME/.local/bin/rpce-headless}`,
installs the staged binary, and runs host-level MCP/agent smokes.
After installing on this machine, the global Codex MCP config should use:

```toml
[mcp_servers.rpce-headless]
command = "/home/ben/.local/bin/rpce-headless"
args = ["serve"]
enabled = true
```

Build or refresh the shared binary with:

```bash
docker run --rm -v "$PWD":/src -w /src swift:6.2.4-noble \
  swift build --product rpce-headless --scratch-path .build-linux
```

Run headless smokes against that binary from inside Docker:

```bash
docker run --rm -v "$PWD":/src -w /src swift:6.2.4-noble \
  bash -lc 'apt-get update >/dev/null && apt-get install -y python3 >/dev/null && \
    python3 Sources/RepoPromptHeadlessServer/Scripts/mcp_smoke.py \
      .build-linux/debug/rpce-headless "$PWD"'
```

Do not run `.build-linux/debug/rpce-headless` directly on the host unless the
host has matching Swift runtime libraries. Prefer running smoke scripts inside
the same `swift:6.2.4-noble` container, or use a small wrapper that execs the
binary inside that container when a smoke expects a local executable path.

Reuse `.build-linux` as the shared Linux SwiftPM scratch path for agent
builds, tests, and smokes in this worktree. Do not create ad hoc sibling
scratch paths such as `.build-linux-review` just to revalidate a diff; rerun
the same Docker command with `--scratch-path .build-linux` so SwiftPM can reuse
the warm checkout/build cache. Smithers review/validate agents should first
read this file, inspect the exact diff, and reuse existing Docker build
evidence for the same tree when it is already available. If independent
validation is still required, use `.build-linux`, not a fresh scratch path.

Focused Linux tests can use the same container/scratch path:

```bash
docker run --rm -v "$PWD":/src -w /src swift:6.2.4-noble \
  swift test --filter <TestName> --scratch-path .build-linux
```

`make dev-swift-build`, `make guardrails`, and the contribution preflight may
still require native host tools such as `swift`, SwiftFormat, SwiftLint, or
`gitleaks`. The contribution preflight uses `swift:6.2.4-noble` automatically
for Swift commands on Linux when native `swift` is absent and that image is
available. In push mode, if SwiftFormat/SwiftLint are missing and the outgoing
Swift changes are confined to `Sources/RepoPromptHeadlessServer`, preflight
runs Docker `rpce-headless` build and smoke evidence instead of native
`dev-lint`; app/shared Swift changes still require the normal style tools.
If a required host tool is still missing, report the host-tool gap separately
from Docker Swift build/smoke evidence.

Stdio `serve` exposes the full headless tool set, including `oracle_send`, `context_builder`, `agent_run`, and `agent_manage`. Socket mode is discovery-restricted:

```bash
.build/debug/rpce-headless serve --root "$PWD" --socket /tmp/rpce.sock
.build/debug/rpce-headless connect --socket /tmp/rpce.sock
```

Discovery sockets expose only status/capabilities, selection, prompt, tree,
search, structure, workspace context, and file reads. They intentionally block
oracle, context builder, and process-backed agent tools. `headless_status` is
transport-aware: on restricted sockets it should report direct evidence tools
as available here and reserve `context_builder`, `agent_manage`, `agent_run`,
and `oracle_send` for full stdio or authenticated full-tool sockets.

Manual headless MCP restart and smoke testing must leave no orphaned
`rpce-headless serve --root "$PWD"` processes. Prefer test harness teardown
(`finally`, `trap`, or explicit stdin close plus `wait`) over commit hooks; hooks
run too late and can kill unrelated side-chat MCP sessions. Before handoff after
manual process testing, verify and clean up only matching processes for this
worktree:

```bash
pgrep -a -f "rpce-headless serve --root $PWD" || true
pkill -TERM -f "rpce-headless serve --root $PWD" || true
```

Oracle-backed headless tools read `RPCE_ORACLE_API_KEY` or `OPENROUTER_API_KEY`; `RPCE_ORACLE_BASE_URL` defaults to OpenRouter and `RPCE_ORACLE_MODEL` defaults to `openrouter/auto`. Use `Sources/RepoPromptHeadlessServer/README.md` for smoke harnesses, Linux artifacts, service setup, and v1 limitations.

## Smithers

Smithers workflows live under `.smithers`. Use Bun package scripts from that directory; the workflow scripts intentionally run the Smithers CLI from the repository root so discovery sees `.smithers/workflows` instead of `.smithers/.smithers/workflows`:

```bash
cd .smithers
bun run typecheck
bun run workflow:list
bun run workflow:run -- plan --prompt "Plan the next change"
bun run gateway
```

The gateway binds to `http://127.0.0.1:7331` by default; override with `HOST` and `PORT`. Workflow UIs are registered from `.smithers/gateway.ts`. Repo validation commands for Smithers are configured in `.smithers/smithers.config.ts` as `make dev-lint` and `make dev-test`.

Use official Smithers docs and CLI output as the source of truth for operating Smithers: `https://smithers.sh/introduction`, `https://smithers.sh/how-it-works`, `https://smithers.sh/llms.txt`, `https://smithers.sh/llms-full.txt`, local `.smithers/node_modules/.bin/smithers docs`, and local `.smithers/node_modules/.bin/smithers docs-full`. Repo-local workflow skills under `.smithers/skills` document this repository's current `.smithers/workflows` pack for future agents. Treat the scaffolded Smithers default workflows as user-owned local source after init: edit them in place, prefer local workflows when names collide, and regenerate repo-local workflow skills when workflow shape or metadata changes:

When a task is multi-step, parallel, retryable, or benefits from independent validation, prefer running the appropriate Smithers workflow instead of ad hoc background subagents. Operate the run yourself: launch it, inspect it, watch node outputs, and integrate the result. Useful operator commands:

```bash
.smithers/node_modules/.bin/smithers inspect <run-id> --watch
.smithers/node_modules/.bin/smithers chat <run-id> --tail 40
.smithers/node_modules/.bin/smithers events <run-id> --group-by node --since 10m
.smithers/node_modules/.bin/smithers node <node-id> --run-id <run-id> --attempts
.smithers/node_modules/.bin/smithers output <run-id> <node-id> --pretty
```

Use `smithers graph <workflow.tsx>` before running to check the initial shape. For conditional workflows, use `smithers graph <workflow.tsx> --run-id <run-id>` after state exists; that renders with run context and can show later-frame nodes that a dry graph cannot. All Smithers commands support `--help`; prefer narrow `logs --tail`, `chat --tail`, `events --node/--type`, and `node --attempts/--tools` over watching noisy foreground stdout.

Keep authoring and validation separate. Seeded workflows such as `create-workflow` can scaffold or revise workflow source, but they are not the validation authority. After any Smithers workflow change, validate the generated or edited workflow with native Smithers commands and repo typecheck:

```bash
cd .smithers
bun run typecheck
bun run workflow:list
cd ..
.smithers/node_modules/.bin/smithers workflow inspect <workflow-id>
.smithers/node_modules/.bin/smithers workflow doctor <workflow-id>
.smithers/node_modules/.bin/smithers graph .smithers/workflows/<workflow-id>.tsx
```

When one of those commands reports a problem, fix from that output. Do not debug a generated workflow by treating the seeded `create-workflow` implementation as the source of truth unless the native validation failure specifically points there.

```bash
cd .smithers
bun run workflow:skills -- --output .smithers/skills --force
```

Committed Smithers source includes `.smithers/agents.ts`, `.smithers/agents`, `.smithers/workflows`, `.smithers/ui`, `.smithers/skills`, config, prompts, and package metadata. Runtime state stays ignored under `.smithers/node_modules`, `.smithers/runs`, `.smithers/executions`, `.smithers/state`, `.smithers/sandboxes`, `.smithers/tmp`, `.smithers/remote`, and `.smithers/dist`.

## Repo-local agent assets

- `.agents/skills`: RepoPrompt CE workflows and contribution/release/test-quality skills. Use the named skill when the user invokes it.
- `.claude` / `.codex`: local agent configuration. Do not expose secrets or machine-local details in summaries.
- `.beads`, `prompt-exports`, `skills-lock.json`: bead metadata, exported prompts, and managed-skill lock state.

Treat these as first-class repo assets when documenting or validating the dirty tree.

## Source placement

See `docs/architecture/source-layout.md` for the full ownership map. Short version:

- Product-flow code: `Sources/RepoPrompt/Features/<FeatureName>`.
- App lifecycle, launch, commands, and composition root: `Sources/RepoPrompt/App`.
- Cross-cutting platform/service substrate: `Sources/RepoPrompt/Infrastructure/<Area>`.
- Bridging-header-sensitive support: `Sources/RepoPrompt/Support`, unless `Package.swift` changes too.
- Shared app/CLI protocol code: `Sources/RepoPromptShared`.
- Test doubles, fixtures, parser inputs, sample projects, and XCTest-only helpers: `Tests/RepoPromptTests`.

App-integrated diagnostics belong under `Sources/RepoPrompt/Features/Diagnostics` with a documented entry point and purpose. Do not recreate legacy top-level buckets (`Views`, `ViewModels`, `Services`, `Models`, `Utils`, `Shared`). Do not put `Tests`, `TestSupport`, or `Fixtures` under `Sources/RepoPrompt`. Keep `MCPControlMessages.swift` single-sourced in `Sources/RepoPromptShared/MCP`.

## Validation choice

Run the smallest check that proves the change:

- Docs only: `git diff --check -- <docs>` plus path/link sanity.
- Swift source: `make dev-format-check`, focused `make dev-test FILTER=...`, or focused `make dev-swift-build PRODUCT=...`.
- Shared MCP or CLI behavior: add `make dev-swift-build PRODUCT=repoprompt-mcp` or `PRODUCT=rpce-headless`.
- Running-app behavior: `make dev-smoke` if the app is already running; `make dev-smoke-launch` only when app launch is approved.
- Smithers changes: from `.smithers`, run `bun run typecheck` and `bun run workflow:list`; for direct CLI use, run `.smithers/node_modules/.bin/smithers ...` from the repository root.
- Source layout changes: `make guardrails`.

Before handoff, report what you ran and what remains unverified. Before commit or push, run the contribution preflight above.
