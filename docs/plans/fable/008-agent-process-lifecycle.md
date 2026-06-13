# Plan 008: Truthful cancellation + owned process groups for headless agent sessions

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `docs/plans/fable/README.md`.
>
> **Drift check (run first)**: `git diff --stat 0bd2270..HEAD -- Sources/RepoPromptHeadlessServer/HeadlessAgentSessionManager.swift Sources/RepoPromptHeadlessServer/HeadlessAgentTypes.swift Sources/RepoPromptHeadlessServer/HeadlessContextBuilderService.swift`
> On any drift, compare the "Current state" excerpts before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M-L
- **Risk**: MED-HIGH (replaces process spawning; mitigated by staged steps, existing smokes after each step, and an explicit fallback STOP)
- **Depends on**: none. Plan 011 (lifecycle smokes) validates this plan's semantics and should land immediately after.
- **Category**: bug (correctness/reliability)
- **Planned at**: commit `0bd2270`, 2026-06-12

## Why this matters

Three related defects make agent cancellation on a long-lived headless server
untrustworthy:

1. `cancel`/`stop_session` mark the session `.cancelled` (a terminal state)
   *before* the child process has exited. Clients are told "dead" while the
   process may run on, and `cleanup_sessions` (gated only on `isTerminal`)
   can delete the session record and temp dir while the process is alive.
2. The process group is set with `setpgid(pid, pid)` from the parent *after*
   `process.run()`. If the child has already `exec`'d, `setpgid` fails
   (silently — the return value is ignored) and the later
   `kill(-pid, SIGTERM)` is a no-op: only the direct child is reliably
   killed; grandchildren (the real agent CLI's subprocesses, e.g. node
   workers) are orphaned.
3. Terminal sessions keep their pipe file handles open until a client
   remembers `cleanup_sessions`, leaking fds on a long-lived daemon; the
   output-capture limit truncates by `Character` count against a byte budget;
   and the SIGKILL escalation runs in an untracked `Task` whose failures are
   silent.

The same post-`run()` `setpgid` race exists in the context builder's
`runAgent`. This plan fixes the spawn primitive once and applies it to both
call sites, and makes cancellation truthful via a new non-terminal
`cancelling` state.

## Current state

All in `Sources/RepoPromptHeadlessServer/` unless noted.

- `HeadlessAgentSessionManager.swift:206-213` — start sequence:

  ```swift
  process.terminationHandler = { [sessionID] process in
      Task { await self.completeSession(sessionID: sessionID, exitCode: process.terminationStatus) }
  }

  do {
      try process.run()
      setProcessGroup(for: process)   // setpgid AFTER run() — racy
  ```

- `HeadlessAgentSessionManager.swift:246-258` — premature terminal state:

  ```swift
  private func cancelRun(arguments: [String: MCP.Value]) async throws -> HeadlessAgentRunSnapshot {
      let sessionID = try requireNonEmptyString(arguments["session_id"], name: "session_id")
      guard let record = sessions[sessionID] else { return expiredSnapshot(sessionID: sessionID) }
      guard !record.status.isTerminal else {
          throw HeadlessToolFailure(message: "Headless agent session '\(sessionID)' is already \(record.status.rawValue).")
      }
      record.cancellationRequested = true
      record.status = .cancelled        // terminal BEFORE the process exits
      record.updatedAt = Date()
      terminate(record.process)
      return snapshot(for: record)
  }
  ```

  `stopSession` (lines ~302-312) has the same `status = .cancelled` +
  `terminate` shape.

- `HeadlessAgentSessionManager.swift:374-385` — `completeSession` guards
  `if record.status == .running` before overwriting status (so a `.cancelled`
  mark survives), drains pipes, nils the readability handlers, but never
  closes the file handles.

- `HeadlessAgentSessionManager.swift:394-409` — `append` computes `allowed`
  in **bytes** but truncates with `text.prefix(allowed)` (**Characters**).

- `HeadlessAgentSessionManager.swift:561-585` — `terminate` + group setup:

  ```swift
  private func terminate(_ process: Process) {
      #if canImport(Darwin) || canImport(Glibc)
          if process.processIdentifier > 0 {
              kill(-process.processIdentifier, SIGTERM)   // result ignored
          }
      #endif
      process.terminate()
      Task {                                              // untracked
          try? await Task.sleep(for: .seconds(2))
          if process.isRunning {
              ... kill(-pid, SIGKILL); kill(pid, SIGKILL) ...
          }
      }
  }

  private func setProcessGroup(for process: Process) {
      #if canImport(Darwin) || canImport(Glibc)
          setpgid(process.processIdentifier, process.processIdentifier)  // result ignored
      #endif
  }
  ```

- `HeadlessAgentTypes.swift:19-27` — the status enum:

  ```swift
  enum HeadlessAgentRunStatus: String, Codable {
      case running
      case completed
      case failed
      case cancelled
      case expired

      var isTerminal: Bool { self != .running }
  }
  ```

- `HeadlessContextBuilderService.swift:274-315` — `runAgent` has the same
  `try process.run(); setpgid(...)` race (lines 292-293) and the same 2s
  SIGTERM→SIGKILL escalation, but it DOES `waitUntilExit` before returning.

- `HeadlessToolSchemas.swift:126` — `agent_manage` `state` filter enum is
  `["running", "completed", "failed", "cancelled"]`.

- Exemplars elsewhere in the repo (read for the pattern; these live in the
  macOS app target — do NOT import them into the headless target):
  - `Sources/RepoPrompt/Infrastructure/Process/ProcessLauncher.swift:142-264` —
    `posix_spawnp` with `posix_spawn_file_actions_t` + `posix_spawnattr_t`
    (`POSIX_SPAWN_SETSIGDEF`; `POSIX_SPAWN_CLOEXEC_DEFAULT` is Darwin-only).
  - `Sources/RepoPrompt/Infrastructure/Process/ProcessTermination.swift:117-157` —
    direct-PID SIGTERM → wait → SIGKILL → `waitpid` reap.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Build | `make dev-swift-build PRODUCT=rpce-headless` | exit 0 |
| Agent smoke | `python3 Sources/RepoPromptHeadlessServer/Scripts/mcp_agent_smoke.py .build/debug/rpce-headless` | `AGENT MCP SMOKE OK` |
| CB MCP smoke | `python3 Sources/RepoPromptHeadlessServer/Scripts/context_builder_mcp_fake_agent_test.py .build/debug/rpce-headless` (confirm argv by reading the script's `main()` first) | `CONTEXT_BUILDER_MCP OK` |
| CB CLI smoke | `python3 Sources/RepoPromptHeadlessServer/Scripts/context_build_fake_agent_test.py .build/debug/rpce-headless` (confirm argv likewise) | `CONTEXT_BUILD OK` |
| Lint / format | `make dev-lint` / `make dev-format` | exit 0 |

## Scope

**In scope** (the only files you should modify):
- `Sources/RepoPromptHeadlessServer/HeadlessProcessGroupLauncher.swift` (create)
- `Sources/RepoPromptHeadlessServer/HeadlessAgentSessionManager.swift`
- `Sources/RepoPromptHeadlessServer/HeadlessAgentTypes.swift`
- `Sources/RepoPromptHeadlessServer/HeadlessContextBuilderService.swift` (Step 7 only)
- `Sources/RepoPromptHeadlessServer/HeadlessToolSchemas.swift` (one enum value, Step 4 only)

**Out of scope**:
- `Sources/RepoPrompt/Infrastructure/Process/*` — exemplars only; the app
  target must not gain headless dependencies or vice versa.
- The Python smoke scripts — plan 011 owns new lifecycle coverage.
- `AgentLauncher.swift`, `ConnectBridge.swift`, `main.swift`.
- Any retention/auto-expiry policy for finished sessions (deferred; see
  Maintenance notes).

## Git workflow

- Branch: `codex/fable-headless-linux` (or child `fable/008-process-lifecycle`).
- Commit per step; run `.agents/skills/rpce-contribution-check/scripts/preflight.sh commit` first.
- No push without operator instruction.

## Steps

### Step 1: Group-owning spawn helper

Create `HeadlessProcessGroupLauncher.swift` with:

```swift
enum HeadlessProcessGroupLauncher {
    struct SpawnedProcess { let pid: pid_t }

    /// Spawns argv[0] (PATH-resolved via posix_spawnp) in a NEW process
    /// group (pgid == child pid), with stdin from /dev/null and
    /// stdout/stderr dup2'd to the provided write fds.
    static func spawn(
        argv: [String],
        environment: [String: String],
        stdoutWriteFD: Int32,
        stderrWriteFD: Int32
    ) throws -> SpawnedProcess
}
```

Implementation requirements (model on `ProcessLauncher.swift:142-264`):
- `#if canImport(Darwin)` / `#elseif canImport(Glibc)` imports, like
  `UnixSocketListener.swift:3-7`.
- `posix_spawn_file_actions_t`: open `/dev/null` O_RDONLY → dup2 to 0;
  dup2 `stdoutWriteFD` → 1; dup2 `stderrWriteFD` → 2.
- `posix_spawnattr_t`: set `POSIX_SPAWN_SETPGROUP` with
  `posix_spawnattr_setpgroup(&attrs, 0)` (pgroup 0 = child's own pid), plus
  `POSIX_SPAWN_SETSIGDEF` as in the exemplar. Guard
  `POSIX_SPAWN_CLOEXEC_DEFAULT` Darwin-only.
- Use `posix_spawnp` so bare command names resolve via PATH (this replaces
  the current `/usr/bin/env` indirection at
  `HeadlessContextBuilderService.swift:276-282`; keep accepting absolute
  argv[0] too — `posix_spawnp` handles both).
- C-string arrays: copy the `strdup`/defer-free pattern from the exemplar.
- Throw `HeadlessToolFailure(message:)` with the errno and argv[0] on failure
  (e.g. "failed to spawn 'claude': errno 2 (No such file or directory)") —
  this message reaches MCP callers, so make it actionable.

Also add a small reaper utility in the same file:

```swift
/// Blocks until pid exits; returns the exit code (WEXITSTATUS) or
/// 128 + signal for signal deaths.
static func reapExitCode(pid: pid_t) -> Int32
```

using `waitpid(pid, &status, 0)` in a retry-on-EINTR loop and:

```swift
let code = (status & 0x7f) == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
```

**Verify**: `make dev-swift-build PRODUCT=rpce-headless` → exit 0.

### Step 2: Switch the session manager to the helper

In `HeadlessAgentSessionManager.swift` `startRun`:
- Keep the two `Pipe()` objects and their `readabilityHandler` blocks exactly
  as today (lines 196-205) — they are the output capture path.
- Replace the `Process` configuration + `process.run()` +
  `setProcessGroup(for:)` with:
  1. `let spawned = try HeadlessProcessGroupLauncher.spawn(argv: launch.argv, environment: launch.environment, stdoutWriteFD: stdoutPipe.fileHandleForWriting.fileDescriptor, stderrWriteFD: stderrPipe.fileHandleForWriting.fileDescriptor)`
  2. Close the parent's copies of the write ends:
     `try? stdoutPipe.fileHandleForWriting.close()` (and stderr) — required
     or EOF never arrives on the read ends.
  3. `record.processID = spawned.pid`
- Replace `process.terminationHandler` with a reaper task stored on the
  record:

  ```swift
  record.reaperTask = Task.detached { [sessionID] in
      let exit = HeadlessProcessGroupLauncher.reapExitCode(pid: spawned.pid)
      await self.completeSession(sessionID: sessionID, exitCode: exit)
  }
  ```

- Update the session record type. NOTE the record ALREADY has
  `var processID: Int32?` (`HeadlessAgentSessionManager.swift:23`) alongside
  `let process: Process` (line 19) — do not add a duplicate field. Remove the
  `process` property, keep `var processID: Int32?` (set it from
  `spawned.pid`), and add `var reaperTask: Task<Void, Never>?` and
  `var escalationTask: Task<Void, Never>?`. Update every `record.process`
  call site (`cancelRun`, `stopSession`, `shutdown`, `terminate`).
- The spawn-failure catch block (current lines 215-221) keeps its cleanup
  (nil handlers, remove session, remove temp dir) and rethrows.
- Delete `setProcessGroup(for:)` entirely.

**Verify**: build exits 0; `mcp_agent_smoke.py` → `AGENT MCP SMOKE OK`.

### Step 3: Truthful cancel via `cancelling`

- `HeadlessAgentTypes.swift`: add `case cancelling` to
  `HeadlessAgentRunStatus`; change
  `var isTerminal: Bool { self != .running && self != .cancelling }`.
- `cancelRun` and `stopSession`: set `record.status = .cancelling` (not
  `.cancelled`), keep `cancellationRequested = true`, call
  `terminate(record:)`. Their returned snapshot now reports `cancelling`.
- `completeSession`: replace the `if record.status == .running` guard with:

  ```swift
  if record.status == .running || record.status == .cancelling {
      record.status = record.cancellationRequested
          ? .cancelled
          : (exitCode == 0 ? .completed : .failed)
  }
  ```

- `waitForSession` needs no change (it already loops until `isTerminal`), so
  `wait` after `cancel` now returns only when the process is truly reaped.
- Check `snapshot(for:)` / `statusText` derivation for an exhaustive switch
  over the enum and add the `cancelling` arm.

**Verify**: build exits 0; `mcp_agent_smoke.py` still passes (it never
cancels).

### Step 4: Expose the new state in the filter enum

`HeadlessToolSchemas.swift:126`: `state` enumValues become
`["running", "cancelling", "completed", "failed", "cancelled"]`.

**Verify**: build exits 0.

### Step 5: Tracked, observable escalation

Rewrite `terminate` to operate on the record:

```swift
private func terminate(record: SessionRecord) {
    guard let pid = record.processID, pid > 0 else { return }
    if kill(-pid, SIGTERM) != 0 && errno != ESRCH {
        fputs("rpce-headless: kill(-\(pid), SIGTERM) failed errno=\(errno)\n", stderr)
    }
    _ = kill(pid, SIGTERM)
    record.escalationTask?.cancel()
    record.escalationTask = Task { [weak self] in
        try? await Task.sleep(for: .seconds(2))
        guard !Task.isCancelled else { return }
        _ = kill(-pid, SIGKILL)
        _ = kill(pid, SIGKILL)
        _ = self // keep actor alive for the duration
    }
}
```

`completeSession` cancels `escalationTask` and `reaperTask` is left to finish
naturally. `shutdown()` iterates non-terminal sessions as today but calls the
new `terminate(record:)`.

**Verify**: build exits 0.

### Step 6: Close fds at terminal + byte-accurate truncation

- `completeSession`: after draining and nil-ing handlers, add
  `try? record.stdoutPipe.fileHandleForReading.close()` and the stderr
  equivalent. Make `cleanupSessions` tolerate already-closed handles (wrap
  its handler-nil + any close in `try?`; it currently only nils handlers and
  removes the temp dir — keep that).
- `append` (lines 394-409): truncate on bytes:

  ```swift
  let prefixBytes = Array(text.utf8.prefix(allowed))
  output += String(decoding: prefixBytes, as: UTF8.self)
  truncated = true
  ```

  (A split multi-byte character decodes to U+FFFD; acceptable, note it in a
  comment.)

**Verify**: build exits 0; `mcp_agent_smoke.py` passes.

### Step 7: Same spawn primitive for the context builder

In `HeadlessContextBuilderService.swift` `runAgent` (lines 274-315):
- Replace `Process` + `setpgid` with `HeadlessProcessGroupLauncher.spawn`,
  passing the write fds of the two pipes already created for
  `prefixPipe(_:label:)`; close parent write ends after spawn.
- Replace `process.waitUntilExit()` with
  `await Task.detached { HeadlessProcessGroupLauncher.reapExitCode(pid: pid) }.value`
  and return that exit code.
- Keep the timeout task's SIGTERM→2s→SIGKILL escalation, but signal `-pid`
  and `pid` directly (no `process.isRunning`; use `kill(pid, 0) == 0` as the
  liveness probe).

**Verify**: build exits 0; both context-build smokes print their OK
sentinels; `mcp_agent_smoke.py` passes.

## Test plan

This plan keeps the three existing smokes green after every step — they cover
the happy path. The new behavioral guarantees (cancel kills the whole tree,
`cancelling` → `cancelled` transition, timeout escalation, missing binary
error) get their executable coverage in **plan 011**, which must land right
after this one. Do not add new Python cases here.

## Done criteria

- [ ] `make dev-swift-build PRODUCT=rpce-headless` exits 0
- [ ] `mcp_agent_smoke.py`, `context_builder_mcp_fake_agent_test.py`, and `context_build_fake_agent_test.py` all print their OK sentinels
- [ ] `grep -rn "setpgid" Sources/RepoPromptHeadlessServer/` → matches only inside `HeadlessProcessGroupLauncher.swift` (if at all)
- [ ] `grep -n "terminationHandler" Sources/RepoPromptHeadlessServer/HeadlessAgentSessionManager.swift` → no matches
- [ ] `grep -n "case cancelling" Sources/RepoPromptHeadlessServer/HeadlessAgentTypes.swift` → 1 match
- [ ] No files outside the in-scope list modified (`git status`)
- [ ] `docs/plans/fable/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- The posix_spawn file-actions/attrs code fails to compile under Glibc after
  two fix attempts (Darwin-only constants are the likely culprit — guard
  them). Report with the compiler errors. The documented fallback (keep
  `Foundation.Process`, check the `setpgid` return value, log group-kill as
  best-effort) is a decision for the reviewer, not for you.
- `Pipe.fileHandleForWriting.fileDescriptor` cannot be safely passed to the
  spawn (fd lifetime issues manifesting as lost output in smokes).
- Any existing smoke regresses and a second fix attempt fails.
- The session record refactor (Process → pid) fans out beyond
  `HeadlessAgentSessionManager.swift`.

## Maintenance notes

- Plan 011 adds the behavioral tests for everything here; if you change the
  `cancelling` semantics, update 011 before executing it.
- Auto-expiry/retention of terminal sessions (temp dirs + records) is still
  client-driven via `cleanup_sessions`; a `RPCE_AGENT_SESSION_RETENTION_SECONDS`
  sweep is deferred — revisit if the VPS daemon accumulates sessions.
- If a future `steer`/`respond` op is ported, stdin is currently /dev/null —
  the spawn helper will need a stdin pipe option.
- Reviewer focus: parent write-end closing (EOF correctness), reaper-vs-
  escalation races, and that `cancel` of an already-`cancelling` session
  still throws the "already" error (it does — `cancelling.isTerminal` is
  false... verify the guard uses `isTerminal`, which now permits a second
  cancel; decide: keep permitting repeat cancel, it is idempotent and safe).
