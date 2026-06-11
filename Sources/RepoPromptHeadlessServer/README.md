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

## Run

```bash
.build/debug/rpce-headless serve --root /path/to/repo
```

Stdout is reserved for newline-delimited JSON-RPC. Diagnostics go to stderr.

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

The server is intentionally single-workspace: run multiple processes for multiple workspaces. `manage_selection` supports `get`, `add`, `remove`, `set`, and `clear`; slices, `preview`, `promote`, and `demote` return explicit unsupported tool errors. Prompt presets/export, mutation tools, git tools, app window/tab routing, native Linux validation, and real-agent template verification are deferred.
