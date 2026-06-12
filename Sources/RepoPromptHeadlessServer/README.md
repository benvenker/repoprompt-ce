# rpce-headless

`rpce-headless` is a standalone MCP server/CLI for the RepoPrompt CE context tools. It loads one logical workspace from one or more `--root` paths and does not require the macOS app.

## Build

```bash
make dev-swift-build PRODUCT=rpce-headless
# or, if the coordinated daemon is unavailable:
swift build --product rpce-headless
```

## Linux Build

The verified Linux target for this fork is Ubuntu 24.04 using the official
Swift image:

```bash
docker run --rm -v "$PWD":/src -w /src swift:6.2.4-noble \
  swift build --product rpce-headless --scratch-path .build-linux
```

The smoke harness needs Python. The official Swift image does not include it,
so install it inside the disposable container or use a derived image:

```bash
docker run --rm -v "$PWD":/src -w /src swift:6.2.4-noble \
  bash -lc 'apt-get update && apt-get install -y python3 && \
  swift build --product rpce-headless --scratch-path .build-linux && \
  python3 Sources/RepoPromptHeadlessServer/Scripts/mcp_smoke.py \
  .build-linux/debug/rpce-headless /src'
```

Expected success output includes `INIT OK` and `ALL OK`.

## Ubuntu VPS Install Sketch

The current deployment shape assumes either a Docker build on the VPS or a
release binary copied from a matching Ubuntu 24.04 build host. The VPS does
not need the macOS app.

```bash
git clone <repo-url> /srv/repoprompt-ce
cd /srv/repoprompt-ce
docker run --rm -v "$PWD":/src -w /src swift:6.2.4-noble \
  swift build -c release --static-swift-stdlib --product rpce-headless --scratch-path .build-linux
install -m 0755 .build-linux/release/rpce-headless /usr/local/bin/rpce-headless
```

`--static-swift-stdlib` avoids requiring a Swift runtime install on the host
where the binary is copied. Omit it only when the target host already provides
the matching Swift runtime libraries.

Create a service user and install the example env/unit files:

```bash
useradd --system --home /srv/repoprompt-ce --shell /usr/sbin/nologin rpce
install -d -m 0750 -o rpce -g rpce /etc/rpce-headless
install -m 0640 -o root -g rpce Sources/RepoPromptHeadlessServer/Examples/rpce-headless.env /etc/rpce-headless/rpce-headless.env
install -m 0644 Sources/RepoPromptHeadlessServer/Examples/rpce-headless.service /etc/systemd/system/rpce-headless.service
systemctl daemon-reload
systemctl enable --now rpce-headless
```

Edit `/etc/rpce-headless/rpce-headless.env` before enabling oracle-backed
tools. The example service exposes a local Unix socket at
`/run/rpce-headless/rpce.sock` for discovery agents. That socket is
discovery-restricted and does not expose `oracle_send`; configure MCP clients
that need `oracle_send` to launch `rpce-headless serve --root ...` over stdio,
or use the `context-build --response-type question|plan` CLI path.

## Run

```bash
.build/debug/rpce-headless serve --root /path/to/repo
```

Stdout is reserved for newline-delimited JSON-RPC. Diagnostics go to stderr.
This stdio mode is intended for MCP clients that launch the process directly;
it exposes all tools, including `oracle_send`.

Socket serving for discovery agents:

```bash
.build/debug/rpce-headless serve --root /path/to/repo --socket /tmp/rpce.sock
.build/debug/rpce-headless connect --socket /tmp/rpce.sock
```

All socket connections are discovery-restricted to:

- `manage_selection`
- `prompt`
- `workspace_context`
- `get_file_tree`
- `get_code_structure`
- `file_search`
- `read_file`

Stdio serving remains unrestricted and includes `oracle_send`.

The socket mode is intended for a local daemon plus discovery agents on the
same host. It does not expose `oracle_send`; use stdio mode or
`context-build --response-type question|plan` for oracle-backed answers.

A diagnostic catalog summary is also available:

```bash
.build/debug/rpce-headless dump --root /path/to/repo
```

## Smoke harness

```bash
python3 Sources/RepoPromptHeadlessServer/Scripts/mcp_smoke.py .build/debug/rpce-headless "$PWD"
```

Expected success output includes `INIT OK` and `ALL OK`.

## Headless context builder

`context-build` starts an in-process restricted Unix socket server, renders a Discover prompt, launches an operator-configured discovery agent, then harvests the resulting selection and prompt:

```bash
.build/debug/rpce-headless context-build \
  --root /path/to/repo \
  --instructions "Map the MCP server entry points" \
  --agent claude
```

Agent templates live in `Examples/agents.json`; operators can copy/edit them at `~/.config/rpce-headless/agents.json` or pass `--agent-config <path>`. Supported placeholders:

- `{PROMPT}`
- `{PROMPT_FILE}`
- `{MCP_CONFIG}`
- `{MCP_CONFIG_PATH_RAW}`
- `{FAKE_AGENT_SCRIPT}` (test harness only)

Dry-run rendering:

```bash
.build/debug/rpce-headless context-build --root "$PWD" --instructions "test" --agent fake --dry-run
```

Offline acceptance:

```bash
python3 Sources/RepoPromptHeadlessServer/Scripts/context_build_fake_agent_test.py .build/debug/rpce-headless "$PWD"
```

Expected success output: `CONTEXT_BUILD OK`.

Pi note: Pi has no built-in MCP hookup in this target. Use the `pi-mcp-adapter` extension with the generated MCP config shape (`command: rpce-headless`, `args: ["connect", "--socket", "<path>"]`). The example `"pi"` agent entry is an operational starting point and remains UNVERIFIED.

## Oracle / OpenRouter

`oracle_send` uses an OpenAI-compatible chat completions endpoint. By default
it targets OpenRouter:

```bash
export RPCE_ORACLE_API_KEY=sk-or-...
export RPCE_ORACLE_BASE_URL=https://openrouter.ai/api/v1
export RPCE_ORACLE_MODEL=openrouter/auto
```

`OPENROUTER_API_KEY` is accepted as a fallback for local shells when
`RPCE_ORACLE_API_KEY` is unset. For a custom OpenAI-compatible endpoint, set
`RPCE_ORACLE_BASE_URL`, `RPCE_ORACLE_API_KEY`, and `RPCE_ORACLE_MODEL` to that
provider's values.

For a new `oracle_send` chat, workspace context is included by default.
Continuations with `chat_id` default to no new context unless
`include_context` is set.

## Tools

- `read_file`
- `get_file_tree`
- `file_search`
- `get_code_structure`
- `manage_selection`
- `workspace_context`
- `prompt`
- `oracle_send` (stdio only)

## v1 semantics and deferred work

The server is intentionally single-workspace: run multiple processes for multiple workspaces. `manage_selection` supports `get`, `add`, `remove`, `set`, and `clear`; slices, `preview`, `promote`, and `demote` return explicit unsupported tool errors. Prompt presets/export, mutation tools, git tools, app window/tab routing, native host service hardening, real-agent template verification, and Swift 6 language-mode warning cleanup in `RepoPromptContextCore` are deferred.
