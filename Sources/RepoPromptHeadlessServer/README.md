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

For the local Codex MCP binary on this Linux machine, prefer the repo helper:

```bash
make headless-linux-install-local
```

It builds the same static Linux artifact in Docker, backs up the existing
`${RPCE_HEADLESS_INSTALL_BIN:-$HOME/.local/bin/rpce-headless}`, installs the
new binary, and verifies the installed host path with MCP/agent smokes.

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
discovery-restricted by default and does not expose `oracle_send`,
`context_builder`, `agent_run`, or `agent_manage`. Use stdio for the full
toolset, or run the socket with `--expose-all-tools` and
`RPCE_SOCKET_AUTH_TOKEN` for an authenticated full-tool socket.

## Run

```bash
.build/debug/rpce-headless serve --root /path/to/repo
```

If `--root` is omitted, `serve` and `dump` load the current working directory.
That is the preferred shape for global MCP client config so each chat/workspace
gets its own repository instead of a hard-coded root.

Stdout is reserved for newline-delimited JSON-RPC. Diagnostics go to stderr.
This stdio mode is intended for MCP clients that launch the process directly;
it exposes all tools, including `oracle_send`, `context_builder`, `agent_run`,
and `agent_manage`.

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

Stdio serving remains unrestricted and includes `oracle_send`,
`context_builder`, `agent_run`, and `agent_manage`.

The socket mode is intended for a local daemon plus discovery agents on the
same host. By default it does not expose `oracle_send`, `context_builder`,
`agent_run`, or `agent_manage`; use stdio mode or
`context-build --response-type question|plan|review` for oracle-backed
answers.

For a full-tool socket, pass `--expose-all-tools` and set
`RPCE_SOCKET_AUTH_TOKEN`. Clients must authenticate before JSON-RPC with one
newline-delimited preamble:

```json
{"rpce_auth":{"token":"<token>"}}
```

The `connect` bridge also accepts `--auth <token>`.

A diagnostic catalog summary is also available:

```bash
.build/debug/rpce-headless dump --root /path/to/repo
```

## Smoke harness

```bash
python3 Sources/RepoPromptHeadlessServer/Scripts/mcp_smoke.py .build/debug/rpce-headless "$PWD"
```

Expected success output includes `INIT OK` and `ALL OK`.

## Linux Artifact

On Ubuntu 24.04 with Swift 6.2.4 and Python 3 available:

```bash
make headless-linux-artifact
# or through the coordinated daemon:
make dev-headless-linux-artifact
```

The artifact path builds a release `rpce-headless` binary with a static Swift
stdlib, runs the MCP/socket/agent/context-builder smoke harnesses, and writes
a tarball, checksum, and manifest under `dist/`. It is intentionally separate
from the macOS app release, notarization, Sparkle, and appcast tooling.

The official `swift:6.2.4-noble` image does not include `make`; install it in
the container or invoke `./Scripts/package_headless_linux.sh` directly.

## Headless context builder

`context-build` starts an in-process restricted Unix socket server, renders a Discover prompt, launches an operator-configured discovery agent, then harvests the resulting selection and prompt. The unrestricted stdio MCP server exposes the same orchestration as the `context_builder` tool; discovery-restricted sockets intentionally do not expose `context_builder`, `oracle_send`, `agent_run`, or `agent_manage`.

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
- `{FAKE_AGENT_SCRIPT}` (automated smoke-test harnesses only)

MCP `context_builder` configuration is resolved from the process environment:

- `RPCE_CONTEXT_BUILDER_AGENT` (defaults to `fake` when `FAKE_AGENT_SCRIPT` is set, otherwise `claude`)
- `RPCE_CONTEXT_BUILDER_AGENT_CONFIG`
- `RPCE_CONTEXT_BUILDER_TIMEOUT_SECONDS`
- `RPCE_CONTEXT_BUILDER_TOKEN_BUDGET`
- `RPCE_CONTEXT_BUILDER_SOCKET_PATH`

MCP `response_type:"clarify"` is offline and only harvests context. `question`, `plan`, and `review` use the oracle after discovery and therefore require oracle API configuration. `export_response:true` is explicitly unsupported by headless v1 and returns a tool error.

MCP callers have two `context_builder` modes:

- Omit `op` for the synchronous compatibility path. This preserves the original one-shot result shape and is appropriate for short deterministic calls:

```json
{"instructions":"Map the MCP server entry points","response_type":"clarify"}
```

- Use the async lifecycle for real configured agents such as Codex, Claude Code, Gemini, or another CLI that can consume the generated MCP config. Keep normal discovery budgets in the 120k-160k range; do not shrink context just to fit a client tool-call deadline.

```json
{"op":"start","instructions":"Map the MCP server entry points","response_type":"clarify","token_budget":160000}
```

The start call returns a compact snapshot with `context_id` and
`run_status:"running"`. Poll or wait on that id without reading
`workspace_context` as a side channel:

```json
{"op":"poll","context_id":"<context_id>"}
{"op":"wait","context_id":"<context_id>","timeout":30}
```

`timeout_seconds` belongs to discovery. Set it on `op:"start"` or in
`RPCE_CONTEXT_BUILDER_TIMEOUT_SECONDS` to cap the spawned discovery-agent
lifetime; an overlong agent fails the run, terminates the process group, and
clears the single-flight active slot. The `timeout` field on `op:"wait"` is
only the client polling deadline; `timeout_seconds` is ignored by `op:"wait"`
and cannot stand in for `timeout`. If that wait expires, the reply includes
`_meta.wait_result:"timed_out"` and the run can still be `running`.

When `run_status` is terminal, fetch the retained result explicitly:

```json
{"op":"get_result","context_id":"<context_id>"}
```

`get_result` returns the same context-builder fields as one-shot mode:
`status`, `prompt`, `selection`, `file_count`, `total_tokens`,
`token_budget`, `response_type`, and any oracle `plan` or `review`. For
failed runs, inspect the snapshot `run_status`, `error`, and optional
`diagnostics`. Failed async runs include diagnostics even when the discovery
agent is quiet: `stdout` and `stderr` are empty, `output_empty` is `true`, and
timeout/process metadata remains available. When the agent does write output,
diagnostics contain bounded discovery-agent stdout/stderr and truncation flags;
the same child output is still forwarded to server stderr with an `agent|`
prefix. Treat these fields as supplementary discovery-agent output, not as
structured tool-call telemetry.

Use `cancel` for active runs that should terminate the spawned discovery-agent
process group. Call `cleanup` after completed, failed, cancelled, or expired
runs to release the retained record and temporary directory. Cleanup skips
active runs and reports unknown or already-cleaned contexts as `not_found`:

```json
{"op":"cancel","context_id":"<context_id>"}
{"op":"cleanup","context_id":"<context_id>"}
```

Headless v1 keeps Context Builder single-flight because selection and prompt
state are shared by the loaded workspace. A second `op:"start"` while another
run is active returns a clear busy error instead of sharing state silently.
Fake agents in this repository are deterministic smoke-test fixtures only.
They are not advertised by default manual/service runs; the fake template is
available only to tests that explicitly provide `FAKE_AGENT_SCRIPT`.
Operators should use their real configured discovery agent.

CLI and MCP names differ slightly: CLI `--response-type selection` maps to
MCP `response_type:"clarify"`. CLI defaults use `claude` with a token budget
of 118,500, while MCP defaults are environment driven (`claude`, 160k for
clarify, 120k otherwise). `question`, `plan`, and `review` invoke the oracle
only after successful, non-empty discovery.

Dry-run rendering:

```bash
.build/debug/rpce-headless context-build --root "$PWD" --instructions "test" --agent claude --dry-run
```

Offline acceptance:

```bash
python3 Sources/RepoPromptHeadlessServer/Scripts/context_build_fake_agent_test.py .build/debug/rpce-headless "$PWD"
python3 Sources/RepoPromptHeadlessServer/Scripts/context_builder_mcp_fake_agent_test.py .build/debug/rpce-headless "$PWD"
```

Expected success output: `CONTEXT_BUILD OK`.

Pi note: Pi has no built-in MCP hookup in this target. Use the `pi-mcp-adapter` extension with the generated MCP config shape (`command: rpce-headless`, `args: ["connect", "--socket", "<path>"]`). The example `"pi"` agent entry is an operational starting point and remains UNVERIFIED.

## Headless agent runner

`agent_run` and `agent_manage` expose a process-backed subset of headless
agent control. They are not app Agent Mode: there is no steering, responding,
worktree management, or app window state. `agent_run` supports
`start`, `poll`, `wait`, and `cancel`; `agent_manage` supports `list_agents`,
`list_sessions`, `get_log`, `stop_session`, and `cleanup_sessions`.

The same `Examples/agents.json` template format drives both `agent_run` and
the context builder. Runtime configuration comes from:

- `RPCE_AGENT_CONFIG` (default `~/.config/rpce-headless/agents.json`)
- `RPCE_AGENT_RUN_DEFAULT_AGENT` (default `claude`)
- `RPCE_AGENT_SOCKET_DIRECTORY` (default temporary directory)
- `RPCE_AGENT_OUTPUT_CAPTURE_LIMIT_BYTES` (default `1000000`)
- `RPCE_CONTEXT_BUILDER_OUTPUT_CAPTURE_LIMIT_BYTES` (falls back to `RPCE_AGENT_OUTPUT_CAPTURE_LIMIT_BYTES`)

Without an operator config, the built-in manual/service agent list contains
real agents only. The `fake` agent is reserved for automated smoke harnesses;
it appears when `FAKE_AGENT_SCRIPT` enables the built-in smoke-test template,
or when an explicit config names an entry that uses `{FAKE_AGENT_SCRIPT}` and
points at the fixture script. Normal manual/service runs should leave
`FAKE_AGENT_SCRIPT` unset and use real agents. If a copied config still
references `{FAKE_AGENT_SCRIPT}` without that environment variable,
`list_agents` reports the entry as unavailable and `agent_run start` rejects
it before spawning.

Call `cleanup_sessions` after terminal runs to reclaim temporary session
directories. Automatic retention sweeping is deferred from headless v1.

`agent_manage get_log` returns a synthetic XML transcript for the session:
prompt, captured stdout, and captured stderr, including truncation attributes.
It does not return a structured MCP tool-call list. Agent text that claims a
tool was used can be useful evidence, but it is not an authoritative audit
trail. Capturing Claude `--output-format stream-json --verbose` events would
require launcher, config, schema, and retention work and is deferred from this
fix.

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
- `agent_run` (stdio / authenticated full-tool socket)
- `agent_manage` (stdio / authenticated full-tool socket)
- `oracle_send` (stdio / authenticated full-tool socket)
- `context_builder` (stdio / authenticated full-tool socket)

## Security notes

Stdio has no MCP-level authentication because the client launches the process
directly. Socket authentication exists only for `serve --socket
--expose-all-tools` with `RPCE_SOCKET_AUTH_TOKEN`; never expose the socket or
a stdio bridge over TCP without adding real authentication and TLS. Any local
process running as the service user can connect to the socket, so use this on
single-tenant hosts.

The example `Examples/agents.json` Claude template uses
`--permission-mode bypassPermissions`. That is a convenience default for
trusted local automation: spawned agents can take arbitrary host actions as
the service user. Review it before VPS deployment, or remove the flag,
sandbox the service user further, and restrict the systemd unit. To rotate the
full-tool socket token, edit the EnvironmentFile and restart
`rpce-headless`.

## v1 semantics and deferred work

The server is intentionally single-workspace: run multiple processes for multiple workspaces. `manage_selection` supports `get`, `add`, `remove`, `set`, and `clear`; slices, `preview`, `promote`, and `demote` return explicit unsupported tool errors. Prompt presets/export, mutation tools, git tools, app window/tab routing, native host service hardening, real-agent template verification, and Swift 6 language-mode warning cleanup in `RepoPromptContextCore` are deferred.
