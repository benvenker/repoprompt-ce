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

Stdio `serve` exposes the full headless tool set, including `oracle_send`, `context_builder`, `agent_run`, and `agent_manage`. Socket mode is discovery-restricted:

```bash
.build/debug/rpce-headless serve --root "$PWD" --socket /tmp/rpce.sock
.build/debug/rpce-headless connect --socket /tmp/rpce.sock
```

Discovery sockets expose only selection, prompt, tree, search, structure, workspace context, and file reads. They intentionally block oracle, context builder, and process-backed agent tools.

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

Smithers has two skill surfaces in this repo. Global agent skills, such as `~/.agents/skills/smithers-*`, teach the current coding agent how to operate Smithers. Repo-local workflow skills under `.smithers/skills` document this repository's current `.smithers/workflows` pack for future agents. Treat the scaffolded Smithers default workflows as user-owned local source after init: edit them in place, prefer local workflows over global defaults when names collide, and regenerate repo-local workflow skills when workflow shape or metadata changes:

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
