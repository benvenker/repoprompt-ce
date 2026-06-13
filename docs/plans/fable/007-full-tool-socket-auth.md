# Plan 007: Authenticated full-tool socket mode (`serve --socket --expose-all-tools`)

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `docs/plans/fable/README.md`.
>
> **Drift check (run first)**: `git diff --stat 0bd2270..HEAD -- Sources/RepoPromptHeadlessServer/`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED (new auth surface; mitigated by default-off flag and a dedicated smoke)
- **Depends on**: none (plan 012 documents the result; land 007 first)
- **Category**: security / direction
- **Planned at**: commit `0bd2270`, 2026-06-12

## Why this matters

Every Unix-socket connection to `rpce-headless` is hard-coded
discovery-restricted: only the 7 deterministic read-only tools are served.
The shipped systemd unit (`Examples/rpce-headless.service:17`) runs socket
mode only, so the headline agentic tools — `agent_run`, `agent_manage`,
`context_builder`, `oracle_send` — are unreachable through the only deployed
transport. The project goal is a shared headless harness that agents on the
VPS can use over MCP, with **one shared workspace state** (selection/prompt)
across connections — which only the socket daemon provides (per-client stdio
gives each client an isolated `HeadlessWorkspaceHost`).

Opening the full toolset on a socket without auth would be an unauthenticated
arbitrary-process-execution surface (agent templates run real CLIs). So this
plan lands **transport and auth as one change**: an opt-in
`--expose-all-tools` serve flag gated by a mandatory shared token. The
decision to use an authenticated full-tool socket (rather than stdio-only
documentation) was made by the repository owner on 2026-06-12.

## Current state

- `Sources/RepoPromptHeadlessServer/HeadlessMCPServer.swift:28-35` — every
  socket connection is restricted:

  ```swift
  func runSocketConnection(fd: Int32) async throws {
      var logger = Logger(label: "rpce-headless.socket")
      logger.logLevel = .warning
      let descriptor = FileDescriptor(rawValue: fd)
      let transport = StdioTransport(input: descriptor, output: descriptor, logger: logger)
      defer { closeDescriptor(fd) }
      try await serve(transport: transport, discoveryRestricted: true)
  }
  ```

  `serve(transport:discoveryRestricted:)` (lines 37-67) picks
  `HeadlessToolSchemas.discoveryTools` vs `.tools`, passes
  `agentSessionManager = discoveryRestricted ? nil : HeadlessAgentSessionManager(host: host)`,
  and rejects non-discovery tool calls with an `isError` result.

- `Sources/RepoPromptHeadlessServer/main.swift:6-23` — the `serve` dispatch:

  ```swift
  case let .serve(roots, socketPath):
      let host = try await HeadlessWorkspaceHost(rootPaths: roots)
      let server = HeadlessMCPServer(host: host)
      if let socketPath {
          let listener = HeadlessUnixSocketListener(path: socketPath)
          try listener.start { fd in
              do {
                  try await HeadlessMCPServer(host: host).runSocketConnection(fd: fd)
              } catch { ... }
          }
          while !Task.isCancelled { try await Task.sleep(for: .seconds(3600)) }
      } else {
          try await server.run()
      }
  ```

- `main.swift:55-105` — `HeadlessCLI.parse`: `Command.serve(roots:socketPath:)`,
  flag loop handles `--root` and `--socket` only. Usage text at
  `main.swift:199-208`.

- `Sources/RepoPromptHeadlessServer/UnixSocketListener.swift:53-67` — accept
  loop hands a bare `Int32` fd to the handler; socket file is `chmod` 0600 at
  line 44. No peer-credential reading anywhere in the headless target.

- `Sources/RepoPromptHeadlessServer/ConnectBridge.swift:9-24` —
  `connect --socket <path>` pumps stdin→socket and socket→stdout with no
  preamble.

- Internal sockets that MUST stay restricted (do not touch their behavior):
  - context-builder discovery socket: `HeadlessContextBuilderService.swift:147-154`
    (`listener.start { ... runSocketConnection(fd:) }`)
  - agent-session callback socket: `HeadlessAgentSessionManager.swift` private
    `ensureSocketServer()` (~lines 414-440), same pattern.

- Env-var convention to match — `HeadlessAgentTypes.swift:9-15` uses
  `environment.headlessTrimmed("RPCE_...")` helpers (defined at
  `HeadlessAgentTypes.swift:197-205`).

- Handshake precedent (exemplar only — different target, do NOT import):
  the app bootstrap socket uses a newline-delimited JSON preamble before the
  main protocol — `Sources/RepoPromptMCP/Shared/MCPBootstrapMessages.swift:35-62`.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Build | `make dev-swift-build PRODUCT=rpce-headless` | exit 0 |
| New smoke | `python3 Sources/RepoPromptHeadlessServer/Scripts/socket_auth_smoke.py .build/debug/rpce-headless` | prints `SOCKET AUTH SMOKE OK` |
| Regression smoke | `python3 Sources/RepoPromptHeadlessServer/Scripts/mcp_smoke.py .build/debug/rpce-headless "$PWD"` | `INIT OK` / `ALL OK` |
| Regression smoke | `python3 Sources/RepoPromptHeadlessServer/Scripts/mcp_agent_smoke.py .build/debug/rpce-headless` | `AGENT MCP SMOKE OK` |
| Lint | `make dev-lint` | exit 0 |
| Format (before handoff) | `make dev-format` | exit 0 |

If `make dev-*` is unavailable (no python3 daemon), fall back to
`swift build --product rpce-headless` and the same smoke commands against
`.build/debug/rpce-headless`.

## Scope

**In scope** (the only files you should modify):
- `Sources/RepoPromptHeadlessServer/main.swift`
- `Sources/RepoPromptHeadlessServer/HeadlessMCPServer.swift`
- `Sources/RepoPromptHeadlessServer/ConnectBridge.swift`
- `Sources/RepoPromptHeadlessServer/Scripts/socket_auth_smoke.py` (create)
- `Sources/RepoPromptHeadlessServer/Examples/rpce-headless.env` (commented token line only)
- `Sources/RepoPromptHeadlessServer/Examples/rpce-headless.service` (commented alternate ExecStart only)

**Out of scope** (do NOT touch, even though they look related):
- `HeadlessContextBuilderService.swift` and `HeadlessAgentSessionManager.swift`
  — their internal callback sockets must remain discovery-restricted and
  unauthenticated (the spawned discovery agents have no token).
- `HeadlessToolSchemas.swift` — no schema changes are needed.
- README prose beyond the two Examples files — plan 012 owns documentation.
- Any TCP/TLS transport. Unix socket only.

## Git workflow

- Work on `codex/fable-headless-linux` (or a child branch `fable/007-socket-auth`).
- Before each commit: `.agents/skills/rpce-contribution-check/scripts/preflight.sh commit`
- Do not push without explicit operator instruction (then run preflight `push` mode).

## Steps

### Step 1: Parse `--expose-all-tools`

In `main.swift`: change `Command.serve(roots:socketPath:)` to
`serve(roots: [String], socketPath: String?, exposeAllTools: Bool)`. In the
serve/dump flag loop (`main.swift:84-103`) accept `--expose-all-tools`
(no value; only valid when `subcommand == "serve"`, mirroring the existing
`--socket` guard). After the loop, reject `--expose-all-tools` without
`--socket`: `throw usage("--expose-all-tools requires --socket")`. Update
`usage()` (line ~202) to
`rpce-headless serve --root <path> [--root <path> ...] [--socket <path> [--expose-all-tools]]`.

**Verify**: `make dev-swift-build PRODUCT=rpce-headless` → exit 0;
`.build/debug/rpce-headless serve --root . --expose-all-tools` → exits 64
with the usage error.

### Step 2: Require the token at startup

In the `case let .serve(...)` dispatch in `main.swift`: when
`exposeAllTools` is true, read the token once:

```swift
let token = ProcessInfo.processInfo.environment["RPCE_SOCKET_AUTH_TOKEN"]?
    .trimmingCharacters(in: .whitespacesAndNewlines)
guard let token, token.count >= 16 else {
    throw HeadlessCLI.ExitError(code: 64, message: "--expose-all-tools requires RPCE_SOCKET_AUTH_TOKEN (>= 16 characters) in the environment")
}
```

Never print or log the token value.

**Verify**: `RPCE_SOCKET_AUTH_TOKEN= .build/debug/rpce-headless serve --root . --socket /tmp/t.sock --expose-all-tools`
→ exits 64 with that message.

### Step 3: Authenticated connection handler

In `HeadlessMCPServer.swift`, add alongside `runSocketConnection(fd:)`
(keep that method byte-for-byte unchanged):

```swift
func runFullAccessSocketConnection(fd: Int32, expectedToken: String) async throws
```

Behavior, in order:
1. Read the first line from `fd` **byte by byte** (single-byte `read(2)`
   calls) up to `\n`, capped at 4096 bytes — byte-by-byte reading guarantees
   no JSON-RPC bytes after the newline are consumed before `StdioTransport`
   takes over. Enforce a 10-second deadline (run the blocking read loop in a
   `Task.detached` and race it against `Task.sleep`; on timeout close the fd
   and return).
2. Parse the line as JSON of shape `{"rpce_auth":{"token":"<value>"}}`
   (use `JSONDecoder` with a small private `Codable` struct).
3. Compare tokens in constant time:

   ```swift
   func constantTimeEquals(_ a: String, _ b: String) -> Bool {
       let lhs = Array(a.utf8), rhs = Array(b.utf8)
       guard !lhs.isEmpty, !rhs.isEmpty else { return false }  // empty token never authenticates; also prevents index trap
       var diff = lhs.count ^ rhs.count
       for i in 0 ..< max(lhs.count, rhs.count) {
           diff |= Int(lhs[i % lhs.count] ^ rhs[i % rhs.count])
       }
       return diff == 0
   }
   ```

   The empty-guard is load-bearing: without it, a client sending
   `{"rpce_auth":{"token":""}}` would trap the daemon on an empty-array
   index. Step 5 includes a regression scenario for exactly this.

4. On mismatch / parse failure / oversized line: write
   `{"rpce_auth":{"status":"rejected"}}\n` to the fd, close, return. Do not
   echo any token material.
5. On success: write `{"rpce_auth":{"status":"accepted"}}\n`, then construct
   `StdioTransport` exactly as `runSocketConnection` does and call
   `try await serve(transport: transport, discoveryRestricted: false)`.

In `main.swift`, route the listener callback to the new handler when
`exposeAllTools` is true; otherwise keep calling `runSocketConnection(fd:)`.

**Verify**: build exits 0.

### Step 4: `connect --auth`

In `main.swift` connect parsing (`main.swift:59-77`) accept an optional
`--auth` flag → `Command.connect(socketPath: String, auth: Bool)`. In
`ConnectBridge.run`, when `auth` is true:
- Read `RPCE_SOCKET_AUTH_TOKEN` from the environment; exit 64 with a clear
  stderr message if missing/empty.
- After `connectSocket`, write the `{"rpce_auth":{"token":...}}\n` line,
  then read one newline-terminated response line from the socket **before**
  starting the pumps. If the response is not `"accepted"`, write
  `rpce-headless connect: socket authentication rejected` to stderr and exit 65.
- The handshake response line must NOT be forwarded to stdout.

When `--auth` is absent, behavior is byte-for-byte today's (so existing
discovery-agent configs keep working against restricted sockets).

**Verify**: build exits 0.

### Step 5: Smoke script

Create `Sources/RepoPromptHeadlessServer/Scripts/socket_auth_smoke.py`,
modeled on the helper/assert style of `mcp_agent_smoke.py` (same
newline-delimited JSON-RPC `rpc`/`notify`/`call` helpers, `assert` failures,
single OK sentinel). Use Python's `socket.socket(socket.AF_UNIX)` to talk to
the socket directly. Scenarios, all against a server started as
`[binary, "serve", "--root", root, "--socket", sock, "--expose-all-tools"]`
with `RPCE_SOCKET_AUTH_TOKEN` set (≥16 chars) plus the fake-HOME env pattern
from `mcp_agent_smoke.py:68-73`:

1. Correct token → handshake `accepted`; `initialize` + `tools/list` over the
   same connection shows all 11 tools including `agent_run`, `agent_manage`,
   `context_builder`, `oracle_send`.
2. Wrong token → handshake line returns `rejected` and the server closes the
   connection (subsequent `recv` returns b"").
   2b. Empty token (`{"rpce_auth":{"token":""}}`) → `rejected`, connection
   closed, AND the daemon survives: a fresh correct-token connection
   immediately afterwards still authenticates and serves `tools/list`.
3. No handshake (send a plain JSON-RPC `initialize` immediately) → connection
   is closed without serving tools (rejected or EOF within ~12s).
4. Control: a second server started WITHOUT `--expose-all-tools` (no token
   env needed) still serves exactly the 7 discovery tools over its socket
   with no handshake — assert `agent_run` absent.
5. Bridge path: run `[binary, "connect", "--socket", sock, "--auth"]` as a
   subprocess with the token in env; speak JSON-RPC over its stdio; assert
   `tools/list` shows the full set and no `rpce_auth` line leaks to stdout.

End with `print("SOCKET AUTH SMOKE OK")`.

**Verify**: `python3 Sources/RepoPromptHeadlessServer/Scripts/socket_auth_smoke.py .build/debug/rpce-headless` → `SOCKET AUTH SMOKE OK`.

### Step 6: Example config breadcrumbs

- `Examples/rpce-headless.env`: append a commented block:

  ```
  # Required only for `serve --socket --expose-all-tools` (full-tool socket).
  # Generate with: openssl rand -hex 32
  # RPCE_SOCKET_AUTH_TOKEN=
  ```

- `Examples/rpce-headless.service`: above the existing `ExecStart` (line 17),
  add a commented alternative:

  ```
  # Full-tool socket (agent_run/agent_manage/context_builder/oracle_send over
  # the socket; requires RPCE_SOCKET_AUTH_TOKEN in the EnvironmentFile):
  #ExecStart=/usr/local/bin/rpce-headless serve --root /srv/repoprompt-ce --socket /run/rpce-headless/rpce.sock --expose-all-tools
  ```

**Verify**: `git diff -- Sources/RepoPromptHeadlessServer/Examples/` shows only
commented additions.

## Test plan

- New: `socket_auth_smoke.py` scenarios 1-5 above (happy auth, wrong token,
  no handshake, default-restricted control, bridge round-trip).
- Regression: `mcp_smoke.py` (stdio unaffected) and `mcp_agent_smoke.py`
  (stdio agent tools + nested restricted-socket assertions unaffected).

## Done criteria

- [ ] `make dev-swift-build PRODUCT=rpce-headless` exits 0
- [ ] `socket_auth_smoke.py` prints `SOCKET AUTH SMOKE OK`
- [ ] `mcp_smoke.py` prints `ALL OK`; `mcp_agent_smoke.py` prints `AGENT MCP SMOKE OK`
- [ ] `grep -n "discoveryRestricted: false" Sources/RepoPromptHeadlessServer/` matches only inside `runFullAccessSocketConnection` (and the stdio `run()` path if it appears there pre-existing)
- [ ] `grep -rn "RPCE_SOCKET_AUTH_TOKEN" Sources/RepoPromptHeadlessServer/*.swift` shows reads only — the value is never interpolated into logs/errors
- [ ] No files outside the in-scope list modified (`git status`)
- [ ] `docs/plans/fable/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- `StdioTransport` fails to operate after the handshake bytes are pre-read
  (e.g. the SDK buffers/validates from byte 0). Report; do not switch to a
  different framing on your own.
- The `MCP.Server`/`StdioTransport` API in `HeadlessMCPServer.swift:28-35`
  does not match the excerpt (SDK drift).
- You find yourself wanting to add a crypto dependency for the comparison —
  don't; the manual constant-time loop is the requirement.
- Any step's verification fails twice after a reasonable fix attempt.

## Maintenance notes

- Token rotation = edit the EnvironmentFile + `systemctl restart rpce-headless`.
  Connections already authenticated stay up; document this in plan 012.
- If TCP exposure is ever wanted, this handshake is NOT sufficient — TLS and
  per-client identity become mandatory. Deliberately out of scope.
- Reviewer focus: the byte-by-byte pre-read (no over-read), the rejected-path
  close, and that the two internal restricted sockets gained no auth path.
- Plan 012 documents the feature in the headless README; keep wording in sync
  with the final flag name.
