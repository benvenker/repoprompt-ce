# Plan 005: Add headless `oracle_send` backed by OpenRouter / any OpenAI-compatible endpoint

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: confirm plan 003 is DONE and its smoke harness
> prints `ALL OK` before starting.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED (network streaming; mitigated by the offline mock gate)
- **Depends on**: plans/003 (server exists). Independent of plan 004 — but
  build for both platforms from the start by following the dependency rules
  below; the Linux gate at the end requires 004 to be DONE.
- **Category**: direction (new capability)
- **Planned at**: commit `1db9bbc`, 2026-06-11
- **Completed at**: 2026-06-11 — macOS headless build, offline mock
  oracle test, missing-key assertion, and plan-003 smoke regression passed.
  Linux container gate was skipped because plan 004 remains blocked by the
  Docker/plan-001 gate.

## Why this matters

`oracle_send` is one of the two agentic features this fork exists for: "ask a
strong model a question over my curated file selection." In the app, this is
`AIQueriesService` streaming through a pool of ~16 provider implementations,
containerized in a `@MainActor` view model. For the headless server we want
ONE provider path that reaches **any** model: an OpenAI-compatible
chat-completions client pointed at OpenRouter (or any custom base URL, incl.
Ollama). We deliberately do NOT port the app's provider stack — SwiftOpenAI/
SwiftAnthropic ride macOS URLSession and the view-model container is
app-bound. A minimal SSE client on AsyncHTTPClient is smaller, cross-platform,
and covers every model OpenRouter fronts.

## Current state

(References are the app's behavior to mirror, not code to port.)

- App streaming core — `Sources/RepoPrompt/Infrastructure/AI/AIQueriesService.swift:296-318`
  (verified): builds an `AsyncThrowingStream`, creates a provider from a pool
  (`let provider = try await self.providerPool.createProvider(for: model)` at
  line 310), then `let providerStream = try await provider.streamMessage(aiMessage, model: model)`
  (line 318), with `defer { Task { await provider.dispose() } }`.
- Provider matrix — `Sources/RepoPrompt/Infrastructure/AI/Providers/AIProviderFactory.swift:164-181`
  (verified): `enum AIProviderType` with 16 cases incl. `.openRouter` and
  `.customProvider`. `OpenRouterProvider.swift` imports `SwiftOpenAI` and
  configures `URLSessionConfiguration.default` (line 31) — this is the stack
  we are NOT porting.
- Chat sessions are Codable models app-side at
  `Sources/RepoPrompt/Features/Chat/Services/ChatSession.swift` — read it for
  the message-shape conventions (roles, stored fields) and mirror the
  *concepts*; do not move the file (it may pull chat UI types).
- The headless server (plan 003) already exposes `workspace_context`
  assembly and selection state via `HeadlessWorkspaceHost` — `oracle_send`'s
  "context" is exactly that assembled text.
- OpenRouter API: OpenAI-compatible `POST {base}/chat/completions` with
  `Authorization: Bearer <key>`, JSON body `{model, messages, stream: true}`;
  SSE response lines `data: {json}` ending with `data: [DONE]`. Default base
  URL `https://openrouter.ai/api/v1`.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Build | `swift build --product rpce-headless` | exit 0 |
| Offline test | `python3 Sources/RepoPromptHeadlessServer/Scripts/oracle_mock_test.py .build/debug/rpce-headless "$PWD"` | `ORACLE OK` |
| Live test (optional) | same script with `--live` and `OPENROUTER_API_KEY` set | `ORACLE LIVE OK` |
| Regression | plan 003 smoke (`mcp_smoke.py`) | `ALL OK` |

## Scope

**In scope**:
- `Package.swift` (add `swift-nio`-based `async-http-client` dependency to the server target only:
  `.package(url: "https://github.com/swift-server/async-http-client.git", from: "1.21.0")`,
  product `AsyncHTTPClient`)
- `Sources/RepoPromptHeadlessServer/**` (new files: `OpenAICompatibleClient.swift`, `OracleService.swift`, `OracleSendTool.swift`, mock-test script)
- `plans/README.md`

**Out of scope** (do NOT touch):
- `Sources/RepoPrompt/**`, `Sources/RepoPromptContextCore/**` (except a
  compiler-demanded `public` — nothing else), `Sources/RepoPromptMCP/**`
- Porting ANY existing provider class (OpenRouterProvider, AnthropicProvider, …)
- API keys in code, config files, or logs — env vars only, never echoed

## Git workflow

- Branch: `headless/005-oracle`. Commit per step. Same preflight note as plan
  002. **Never commit anything containing an API key — the preflight secret
  scan failing is always a STOP.**

## Steps

### Step 1: `OpenAICompatibleClient`

New file `Sources/RepoPromptHeadlessServer/OpenAICompatibleClient.swift` —
a small actor/struct on `AsyncHTTPClient`:

```swift
struct OracleConfig {
    let baseURL: String      // env RPCE_ORACLE_BASE_URL, default "https://openrouter.ai/api/v1"
    let apiKey: String       // env RPCE_ORACLE_API_KEY (fallback: OPENROUTER_API_KEY)
    let defaultModel: String // env RPCE_ORACLE_MODEL, default "openrouter/auto"
}

struct ChatMessage: Codable { let role: String; let content: String }

func streamChat(messages: [ChatMessage], model: String, config: OracleConfig)
    -> AsyncThrowingStream<String, Error>   // yields content deltas
```

Implementation requirements:
- `HTTPClientRequest` to `\(baseURL)/chat/completions`, method POST, headers
  `Authorization: Bearer …`, `Content-Type: application/json`; body
  `{ "model": model, "messages": messages, "stream": true }`.
- Read the response body as a byte stream; split on newlines; for each line
  starting with `data: `: if payload is `[DONE]` finish; else JSON-decode and
  yield `choices[0].delta.content` when present. Ignore empty/comment lines.
  Buffer partial lines across chunks (SSE events can split mid-line).
- Non-2xx → throw with status + first 500 bytes of body.
- 10-minute total timeout; client shut down on dispose.

**Verify**: `swift build --product rpce-headless` → exit 0.

### Step 2: `OracleService` + sessions

New file `OracleService.swift` (actor):
- `func send(message: String, chatID: String?, model: String?, includeContext: Bool) async throws -> (chatID: String, stream: AsyncThrowingStream<String, Error>)`
- Builds messages: system prompt (constant: a brief "you are a senior
  engineer answering over the provided repository context" — keep under 10
  lines), then for `includeContext == true` a user message containing the
  `workspace_context` assembly from `HeadlessWorkspaceHost` (same text the
  tool returns), then prior turns from the session, then the new message.
- Sessions persist as JSON at
  `<stateDir>/chats/<chatID>.json` where `stateDir` =
  `$XDG_STATE_HOME/rpce-headless` or `~/.local/state/rpce-headless` (Linux) /
  `~/Library/Application Support/rpce-headless` (macOS). Shape:
  `{id, createdAt, model, messages: [ChatMessage]}` — mirror the field naming
  conventions you saw in `ChatSession.swift`. Assistant reply is appended
  after the stream completes.

**Verify**: build exits 0.

### Step 3: the `oracle_send` tool

Register tool `oracle_send` in the plan-003 server:
- Schema: `message` (string, required), `chat_id` (string, optional —
  continue a chat), `model` (string, optional), `include_context` (bool,
  default true on first turn of a chat, false on continuations — state it in
  the description).
- Handler: run `OracleService.send`, **accumulate the deltas**, return one
  text content block: the full reply, prefixed by a single metadata line
  `chat_id: <id> | model: <model>`. (MCP progress streaming is a deferred
  nicety; a complete reply is fine for v1.)
- Missing `RPCE_ORACLE_API_KEY`/`OPENROUTER_API_KEY` → tool returns an
  `isError` result with a clear one-line message (server still starts fine —
  deterministic tools must not be affected).

**Verify**: build; then `mcp_smoke.py` still prints `ALL OK` (no regression),
and `tools/list` now contains `oracle_send` (extend the smoke's expected set).

### Step 4: offline mock gate

Create `Sources/RepoPromptHeadlessServer/Scripts/oracle_mock_test.py`:

```python
#!/usr/bin/env python3
# Starts a local OpenAI-compatible mock (SSE), points rpce-headless at it,
# calls oracle_send over MCP stdio, asserts the streamed reply round-trips.
import json, os, subprocess, sys, threading, itertools
from http.server import BaseHTTPRequestHandler, HTTPServer
binary, root = sys.argv[1], sys.argv[2]
live = "--live" in sys.argv

class Mock(BaseHTTPRequestHandler):
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        assert self.headers["Authorization"].startswith("Bearer "), "missing bearer"
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream"); self.end_headers()
        for chunk in ["MOCK_", "REPLY_", "OK"]:
            evt = {"choices":[{"delta":{"content":chunk}}]}
            self.wfile.write(f"data: {json.dumps(evt)}\n\n".encode()); self.wfile.flush()
        self.wfile.write(b"data: [DONE]\n\n")
    def log_message(self, *a): pass

env = dict(os.environ)
if not live:
    srv = HTTPServer(("127.0.0.1", 0), Mock)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    env["RPCE_ORACLE_BASE_URL"] = f"http://127.0.0.1:{srv.server_port}/v1"
    env["RPCE_ORACLE_API_KEY"] = "mock-key"
    env["RPCE_ORACLE_MODEL"] = "mock-model"

p = subprocess.Popen([binary, "serve", "--root", root], stdin=subprocess.PIPE,
                     stdout=subprocess.PIPE, stderr=sys.stderr, text=True, env=env)
ids = itertools.count(1)
def rpc(method, params=None):
    i = next(ids)
    p.stdin.write(json.dumps({"jsonrpc":"2.0","id":i,"method":method,"params":params or {}})+"\n"); p.stdin.flush()
    while True:
        msg = json.loads(p.stdout.readline())
        if msg.get("id") == i:
            assert "error" not in msg, msg["error"]; return msg["result"]
def notify(m, prm=None):
    p.stdin.write(json.dumps({"jsonrpc":"2.0","method":m,"params":prm or {}})+"\n"); p.stdin.flush()
rpc("initialize", {"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"0"}})
notify("notifications/initialized")
r = rpc("tools/call", {"name":"oracle_send","arguments":{"message":"ping","include_context":False}})
text = "".join(c.get("text","") for c in r.get("content",[]))
assert not r.get("isError"), text[:400]
if live:
    assert len(text.split("|",1)[-1].strip()) > 0; print("ORACLE LIVE OK")
else:
    assert "MOCK_REPLY_OK" in text, text[:400]
    # continuation: same chat_id second turn must not error
    cid = text.split("chat_id:",1)[1].split("|")[0].strip()
    r2 = rpc("tools/call", {"name":"oracle_send","arguments":{"message":"again","chat_id":cid}})
    assert not r2.get("isError")
    print("ORACLE OK")
p.stdin.close(); p.wait(timeout=10)
```

**Verify**: `python3 …/oracle_mock_test.py .build/debug/rpce-headless "$PWD"` → `ORACLE OK`.
Then check the session file exists: `ls ~/Library/Application\ Support/rpce-headless/chats/` (macOS) → one JSON file containing both turns.

### Step 5 (gate only when plan 004 is DONE): Linux check

Run the mock test inside the plan-004 Docker image (build with
`--scratch-path .build-linux` first). AsyncHTTPClient is a server-side-Swift
library — it is expected to just work. → `ORACLE OK` in container.

## Test plan

- The mock test is the acceptance test (checked in beside `mcp_smoke.py`).
- Cases covered: bearer header sent, SSE parse incl. multi-chunk, [DONE]
  termination, session continuation, missing-key error path (add one extra
  assertion: unset the key env vars, call `oracle_send`, expect `isError`).

## Done criteria

- [x] `swift build --product rpce-headless` exits 0 (macOS; local
  validation used non-escalated `--disable-sandbox` because SwiftPM's
  internal manifest sandbox is unavailable in this agent session)
- [x] `oracle_mock_test.py` prints `ORACLE OK`
- [x] Missing-key call returns `isError: true`, server keeps serving
- [x] `mcp_smoke.py` still prints `ALL OK`
- [ ] If plan 004 DONE: mock test prints `ORACLE OK` in the Linux container
  — skipped; blocked by plan 004 / Docker plan-001 gate
- [x] `grep -rn "sk-or-\|Bearer " Sources/ | grep -v "Bearer \\\\("` shows no hardcoded keys (manual eyeball; grep exclusion pattern needed manual equivalent because the literal pattern is invalid for local grep)
- [x] `plans/README.md` updated

## STOP conditions

- AsyncHTTPClient fails to resolve/build against the repo's pinned
  swift-nio-adjacent dependencies (report the resolution conflict verbatim).
- SSE parsing cannot be made to pass the mock after two attempts (report the
  raw bytes captured from the mock).
- You find yourself wanting to modify `AIQueriesService` or any app provider
  — that's out of scope by design; re-read "Why this matters".

## Maintenance notes

- Adding Anthropic-native (or any other) API support later = a second
  implementation behind the same `streamChat` seam, selected by config — do
  not branch inside the client.
- If MCP progress notifications are added later, the accumulate-then-return
  handler in Step 3 is the seam to upgrade.
- Reviewer focus: SSE line-buffering correctness and that no key material
  can reach logs or committed files.
