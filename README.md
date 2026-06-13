# RepoPrompt CE

[![CI](https://github.com/repoprompt/repoprompt-ce/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/repoprompt/repoprompt-ce/actions/workflows/ci.yml?query=branch%3Amain)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
![Platform: macOS 26+](https://img.shields.io/badge/platform-macOS%2026%2B-black)

RepoPrompt CE is a free, open-source native macOS app for context engineering
and agent orchestration. It builds reviewable repository context from files,
CodeMaps, trees, selections, and diffs, then exposes that context through the
app, MCP, headless tools, Smithers workflows, and agent skills.

## Quick Start

Install the signed public app:

```bash
brew tap repoprompt/repoprompt-ce
brew install --cask repoprompt-ce
```

Build and relaunch the local debug app:

```bash
./conductor app relaunch
```

If signing is unavailable, use ad-hoc signing. Ad-hoc debug builds use
in-memory secure storage, so saved API keys and secure permission changes do
not persist across launches.

```bash
ALLOW_ADHOC_SIGNING=1 ./conductor app relaunch
```

Finder launchers:

- [`Launch RepoPrompt CE.command`](Launch%20RepoPrompt%20CE.command): debug
  build and relaunch
- [`Install RepoPrompt CE Local Production.command`](Install%20RepoPrompt%20CE%20Local%20Production.command):
  local release-mode app under `/Applications`

Source-build requirements: macOS 26+, Xcode 26 or matching Command Line Tools,
and Python 3 for the coordinated developer daemon.

## Agent Entry Points

Read [`AGENTS.md`](AGENTS.md) before editing. It owns coordinated builds,
tests, app launches, live MCP checks, source placement, and pre-commit
preflight.

Common coordinated commands:

```bash
make dev-build
make dev-test
make dev-test FILTER=WorkspaceFileContextStoreTests
make dev-lint
make dev-smoke
```

The `dev-*` targets route through `./conductor`, which serializes build, test,
style, and live-app lanes so agents do not collide over `.build` or the running
app.

Committed agent assets in this checkout:

- [`.agents/skills/`](.agents/skills/): RepoPrompt workflow skills and `rpce-*`
  project skills
- [`.claude/`](.claude/) and [`.codex/`](.codex/): local agent configuration
- [`.beads/`](.beads/): Beads issue state for `repoprompt-ce`
- [`prompt-exports/`](prompt-exports/) and [`skills-lock.json`](skills-lock.json):
  exported oracle prompts and the skill lockfile

## Headless MCP

[`rpce-headless`](Sources/RepoPromptHeadlessServer) is a standalone MCP server
and CLI for RepoPrompt CE context tools. It does not require the macOS app.

```bash
make dev-swift-build PRODUCT=rpce-headless
.build/debug/rpce-headless serve --root "$PWD"
.build/debug/rpce-headless context-build --root "$PWD" --instructions "Map the MCP server" --agent fake --dry-run
```

Stdio `serve` exposes the full headless tool set, including `oracle_send`,
`context_builder`, `agent_run`, and `agent_manage`. Socket connections are
discovery-restricted by default to read/search/selection tools. The full guide
is [`Sources/RepoPromptHeadlessServer/README.md`](Sources/RepoPromptHeadlessServer/README.md).

## Smithers

Smithers workflows live in [`.smithers/`](.smithers/). The pack is a
Bun/TypeScript workspace with local scripts in
[`.smithers/package.json`](.smithers/package.json), agent pools in
[`.smithers/agents.ts`](.smithers/agents.ts), workflow UIs in
[`.smithers/ui/`](.smithers/ui/), and workflow graphs in
[`.smithers/workflows/`](.smithers/workflows/).

From the repository root:

```bash
cd .smithers
bun install
bun run workflow:list
bun run workflow:run -- plan --prompt "Plan the next change"
bun run gateway
```

The workflow package scripts run Smithers from the repository root so discovery
sees `.smithers/workflows`; direct CLI use should do the same, for example
`.smithers/node_modules/.bin/smithers workflow list`. `bun run workflow:list`
prints the local workflow catalog. The gateway
defaults to `http://127.0.0.1:7331` and mounts UIs for core workflows such as
`plan`, `implement`, `research-plan-implement`, `review`, `kanban`, `mission`,
`workflow-skill`, and `vcs`. Override the bind address with `HOST` and `PORT`.

Smithers runtime state stays out of git under `.smithers/runs`,
`.smithers/executions`, `.smithers/state`, `.smithers/sandboxes`, and
`.smithers/tmp`; see [`.smithers/.gitignore`](.smithers/.gitignore).

## Where To Look

- App and MCP: [`Sources/RepoPrompt`](Sources/RepoPrompt),
  [`Sources/RepoPromptMCP`](Sources/RepoPromptMCP), and
  [`Sources/RepoPromptHeadlessServer`](Sources/RepoPromptHeadlessServer)
- Shared context: [`Sources/RepoPromptContextCore`](Sources/RepoPromptContextCore)
  and [`Sources/RepoPromptShared`](Sources/RepoPromptShared)
- Providers: [`Packages/RepoPromptAgentProviders`](Packages/RepoPromptAgentProviders)
- Agent tooling: [`.smithers/`](.smithers/), [`.agents/skills/`](.agents/skills/),
  and [`.beads/`](.beads/)
- Contributor docs: [`CONTRIBUTING.md`](CONTRIBUTING.md),
  [`docs/architecture/source-layout.md`](docs/architecture/source-layout.md),
  [`docs/architecture/provider-plugins.md`](docs/architecture/provider-plugins.md),
  [`docs/worktrees.md`](docs/worktrees.md), [`docs/releasing.md`](docs/releasing.md),
  and [`docs/open-source-readiness.md`](docs/open-source-readiness.md)

## License

RepoPrompt CE is licensed under [Apache-2.0](LICENSE).
