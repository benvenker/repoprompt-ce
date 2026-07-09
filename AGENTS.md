# Agent Notes

RepoPrompt CE is a Swift Package macOS app plus a standalone Swift headless MCP
server. `CLAUDE.md` is a symlink to this file. Keep this file as a router; put
long procedures in the docs it points to.

## First Moves

- Run `git status --short --branch` before edits. The tree often contains
  intended local work; do not revert or clean user changes unless asked.
- Use Honcho MCP for creating or managing memories.
- Prefer `rg` / `rg --files` for local search.
- Prefer `./conductor` or `make dev-*` for builds, tests, runs, formatting, and
  release checks. Use direct `swift`, `make build`, `make run`, or `make test`
  only as fallbacks.
- Ask for explicit approval immediately before force-push, history rewrite,
  branch deletion, fork deletion, credential rotation, GitHub-visible
  destructive mutation, visible app launch/relaunch, or stopping a visible app.

## Task Router

| Task | Start Here | Notes |
| --- | --- | --- |
| Headless MCP / Linux / Fable | `Sources/RepoPromptHeadlessServer/README.md`, `docs/plans/fable/README.md` | Linux means the Swift `rpce-headless` target on Linux, not a separate non-Swift service. |
| App-backed MCP vs headless tool parity | `docs/investigations/feature-parity/app-vs-headless-parity-design.md`, `docs/plans/2026-06-18-001-feat-app-headless-parity-lane-index-plan.md` | Treat the macOS app as reference material unless asked to change it. |
| Issue tracker / PRDs | `docs/agents/issue-tracker.md` | Use `gh` for `benvenker/repoprompt-ce`. |
| Triage labels | `docs/agents/triage-labels.md` | Canonical labels: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. |
| Domain language | `CONTEXT.md`, `docs/agents/domain.md`, `docs/adr/` | This is a single-context repo; use the glossary terms. |
| Source placement | `docs/architecture/source-layout.md` | Do not recreate legacy top-level buckets such as `Views`, `ViewModels`, `Services`, `Models`, `Utils`, or `Shared`. |
| Smithers workflows | `.smithers/`, `docs/architecture/smithers-beads-workflows.md` | Operate runs yourself; inspect outputs and integrate results. |
| Release / contribution gate | `.agents/skills/rpce-contribution-check/` | Read and run this skill before commit or push. |

## Headless Boundary

`rpce-headless` is the SwiftPM product backed by `RepoPromptHeadlessServer`,
`RepoPromptContextCore`, and `RepoPromptShared`.

- Fable/headless Linux work means build, package, install, and smoke-test that
  Swift MCP server on Linux.
- Do not wholesale-port the app provider stack or `MCPWindowToolDependencies`
  into headless. Add narrow headless handlers over `RepoPromptContextCore`.
- App-side code under `Sources/RepoPrompt` is reference material for headless
  work unless the user explicitly asks to change the app.
- App-parity ideas such as steering, responding, worktrees, app tabs, and native
  workflow execution are planned work, not assumed present.

Discover the headless contract from the tool:

```bash
rpce-headless robot-docs status --json
rpce-headless capabilities --json
rpce-headless robot-docs guide
rpce-headless dump --json
```

For architecture onboarding, call `headless_status` first, use
`context_builder` for curated discovery, then verify with tree/search/read
tools. For independent review, use the server-managed lifecycle:
`agent_manage list_agents` -> bounded read-only `agent_run` -> inspect logs ->
`agent_manage cleanup_sessions`.

## Linux VPS Headless Lane

On Linux, especially `ben-netcup-v2`, do not assume Swift is unavailable just
because `swift` is missing from `PATH`. Check Docker Swift too:

```bash
command -v swift || true
docker images --format '{{.Repository}}:{{.Tag}}' | grep '^swift:' || true
docker run --rm swift:6.2.4-noble swift --version
```

Use `swift:6.2.4-noble` and the shared `.build-linux` scratch path for Linux
builds, tests, and smokes. Do not create ad hoc sibling scratch paths just to
revalidate a diff.

```bash
docker run --rm -v "$PWD":/src -w /src swift:6.2.4-noble \
  swift build --product rpce-headless --scratch-path .build-linux
```

Prefer the static installer for this machine's Codex MCP binary:

```bash
make headless-linux-install-local
```

Do not run `.build-linux/debug/rpce-headless` directly on the host unless the
host has matching Swift runtime libraries. Smoke it inside the Swift container,
or install the static artifact. Global Codex MCP config should launch
`rpce-headless serve` without `--root` so each workspace supplies its own root.

Manual headless MCP testing must leave no orphaned server processes for this
worktree:

```bash
pgrep -a -f "rpce-headless serve --root $PWD" || true
pkill -TERM -f "rpce-headless serve --root $PWD" || true
```

## MCP Surfaces

Use the CE debug CLI for this repo. Production `rp-cli` / `rp-cli-debug` may
talk to the non-CE app.

```bash
make debug-cli-status
make install-debug-cli
```

Fallback debug CLI path:

```bash
"$HOME/Library/Application Support/RepoPrompt CE/repoprompt_ce_cli_debug" -e 'windows'
```

For running the app, use `make dev-run`. For user-directed newest lifecycle,
use `./conductor app relaunch` only after explicit approval when it affects the
visible app.

## Smithers

Smithers workflows live under `.smithers`. Run package scripts from that
directory; direct CLI invocations should run from the repository root so
discovery sees `.smithers/workflows`.

```bash
cd .smithers
bun run typecheck
bun run workflow:list
bun run workflow:run -- plan --prompt "Plan the next change"
bun run gateway
```

For multi-step, parallel, retryable, or independently validated work, prefer an
appropriate Smithers workflow over ad hoc background subagents. Keep tickets to
bounded state transitions: read current state, read desired state, make one
incremental change, validate/review, then repeat only if the next state is
clear.

Useful operator commands:

```bash
.smithers/node_modules/.bin/smithers inspect <run-id> --watch
.smithers/node_modules/.bin/smithers chat <run-id> --tail 40
.smithers/node_modules/.bin/smithers events <run-id> --group-by node --since 10m
.smithers/node_modules/.bin/smithers node <node-id> --run-id <run-id> --attempts
.smithers/node_modules/.bin/smithers output <run-id> <node-id> --pretty
```

After Smithers workflow changes, validate with native Smithers commands and repo
typecheck. Regenerate repo-local workflow skills when workflow shape or metadata
changes:

```bash
cd .smithers
bun run typecheck
bun run workflow:list
bun run workflow:skills -- --output .smithers/skills --force
```

Runtime state stays ignored under `.smithers/node_modules`, `.smithers/runs`,
`.smithers/executions`, `.smithers/state`, `.smithers/sandboxes`,
`.smithers/tmp`, `.smithers/remote`, and `.smithers/dist`.

## Git And Preflight

Before every commit or push, read and run the repository-local
`$rpce-contribution-check` skill.

```bash
.agents/skills/rpce-contribution-check/scripts/preflight.sh commit
.agents/skills/rpce-contribution-check/scripts/preflight.sh push
```

- Commit mode is required after staging and must be rerun after any staging
  change, including partial staging.
- Push mode requires a clean working tree after committing and before pushing.
- Stage only intended files.
- Keep local `docs/investigations/*.md` reports unstaged unless the user asks
  to commit them.
- Versioned hooks live in `.githooks/`; enable with
  `git config core.hooksPath .githooks`.

## Validation Router

Run the smallest check that proves the change:

| Change | Validation |
| --- | --- |
| Docs only | `git diff --check -- <paths>` plus link/path sanity |
| Swift source | `make dev-format-check`, focused `make dev-test FILTER=...`, or focused `make dev-swift-build PRODUCT=...` |
| Shared MCP / CLI | Add `make dev-swift-build PRODUCT=repoprompt-mcp` or `PRODUCT=rpce-headless` |
| Running app behavior | `make dev-smoke` if already running; `make dev-smoke-launch` only with app-launch approval |
| Smithers | From `.smithers`: `bun run typecheck` and `bun run workflow:list` |
| Source layout | `make guardrails` |

Before handoff, report what you ran and what remains unverified.

## Repo Assets

- `.agents/skills`: RepoPrompt CE workflows and contribution/release/test-quality
  skills. Use the named skill when invoked.
- `.smithers`: workflow source, prompts, skills, UI, config, and package
  metadata.
- `.claude` / `.codex`: local agent configuration. Do not expose secrets or
  machine-local details in summaries.
- `.beads`, `prompt-exports`, `skills-lock.json`: planning metadata, exported
  prompts, and managed-skill lock state.

Treat these as first-class repo assets when documenting or validating a dirty
tree.
