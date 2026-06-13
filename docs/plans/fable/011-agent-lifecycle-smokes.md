# Plan 011: Behavioral lifecycle smokes for agent_run/agent_manage (+ wire smokes into validation)

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `docs/plans/fable/README.md`.
>
> **Drift check (run first)**: confirm plan 008 is DONE in
> `docs/plans/fable/README.md` (this plan asserts 008's `cancelling` →
> `cancelled` semantics). Then
> `git diff --stat 0bd2270..HEAD -- Sources/RepoPromptHeadlessServer/Scripts/ Scripts/package_headless_linux.sh Makefile`

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW-MED (test-only code paths; flakiness is the main risk — use generous timeouts)
- **Depends on**: plan 008 (cancel semantics + group kill are what these smokes prove)
- **Category**: tests
- **Planned at**: commit `0bd2270`, 2026-06-12

## Why this matters

The existing smokes prove only the happy path: a fake agent that starts,
prints, and exits 0. Nothing executable covers the behaviors a VPS will hit
first: `cancel`/`stop_session` actually killing the process tree,
`detach: true` + later `poll`/`wait`, `wait` timeouts, a missing agent
binary, or two concurrent sessions. Worse, of the four existing smoke
scripts only `mcp_smoke.py` is wired into any validation flow
(`Scripts/package_headless_linux.sh:53-54`); the agent and context-builder
smokes run only when someone remembers to run them.

## Current state

- `Sources/RepoPromptHeadlessServer/Scripts/mcp_agent_smoke.py` (184 lines) —
  the structural exemplar. Key pieces to reuse:
  - embedded fake agent heredoc `FAKE_AGENT = r'''...'''` (lines 12-58):
    prints `RPCE_AGENT_SMOKE_SENTINEL:<prompt>` from `RPCE_DISCOVER_PROMPT`,
    then connects back to the restricted MCP socket from
    `cfg["mcpServers"]["repoprompt"]` (its own nested `rpc` helper) and
    asserts agent tools are blocked there.
  - `start_server(binary, root, fake_agent, agent_config)` (lines 67-79):
    env sets `FAKE_AGENT_SCRIPT`, `RPCE_AGENT_CONFIG`,
    `RPCE_AGENT_RUN_DEFAULT_AGENT=fake`, fake `HOME`/`CFFIXED_USER_HOME`;
    argv `[binary, "serve", "--root", str(root)]`.
  - JSON-RPC helpers `rpc`/`notify`/`call`/`payload` (lines 109-135),
    newline-delimited framing, plain `assert` failures.
  - Scenario (lines 138-170): tools/list → list_agents → start
    (`detach: False`) → list_sessions → get_log → cleanup_sessions →
    `AGENT MCP SMOKE OK`.
- Post-008 semantics to assert (read `HeadlessAgentSessionManager.swift`
  after 008 lands): `cancel` → snapshot status `cancelling`; subsequent
  `wait` → `cancelled` once the process is reaped; `wait` returns
  `meta.wait_result == "timed_out"` with status `running` when the deadline
  passes; spawn failure for a missing binary surfaces as an MCP tool error
  naming the executable; `cleanup_sessions` skips non-terminal sessions with
  reason `skipped_active`.
- `Scripts/package_headless_linux.sh:53-54` — the only wired smoke:

  ```bash
  printf '==> Running headless MCP smoke\n'
  python3 "$ROOT_DIR/Sources/RepoPromptHeadlessServer/Scripts/mcp_smoke.py" "$BINARY" "$ROOT_DIR"
  ```

- `Makefile` has `headless-linux-artifact` (delegates to that script) but no
  target that runs the headless smokes against a local debug build.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Build | `make dev-swift-build PRODUCT=rpce-headless` | exit 0 |
| New smoke | `python3 Sources/RepoPromptHeadlessServer/Scripts/mcp_agent_lifecycle_smoke.py .build/debug/rpce-headless` | `AGENT LIFECYCLE SMOKE OK` |
| Existing smokes | the four existing scripts as documented in their `main()` | each OK sentinel |
| All headless smokes | `make headless-smoke` (created in Step 4) | all sentinels, exit 0 |

## Scope

**In scope**:
- `Sources/RepoPromptHeadlessServer/Scripts/mcp_agent_lifecycle_smoke.py` (create)
- `Scripts/package_headless_linux.sh` (add smoke invocations)
- `Makefile` (new `headless-smoke` target)

**Out of scope**:
- Any Swift source change. If a scenario fails because the server behaves
  wrongly, that is a finding to report, not to patch here.
- Refactoring the four existing scripts into a shared module (real
  duplication exists — `rpc`/`notify`/`call` are repeated per script — but
  consolidation is explicitly deferred; copy the helpers once more).
- conductor.py lanes (a coordinated `headless-smoke` daemon job is a
  nice-to-have; defer).

## Git workflow

- Branch: `codex/fable-headless-linux` (or child `fable/011-lifecycle-smokes`).
- Preflight before each commit: `.agents/skills/rpce-contribution-check/scripts/preflight.sh commit`
- No push without operator instruction.

## Steps

### Step 1: Script skeleton + sleeping fake agent

Create `mcp_agent_lifecycle_smoke.py` copying the argv parsing,
`start_server`, and `rpc`/`notify`/`call`/`payload` helpers from
`mcp_agent_smoke.py` verbatim. Define a second fake agent heredoc
`SLEEPING_AGENT` with knobs read from env:

```python
SLEEPING_AGENT = r'''
#!/usr/bin/env python3
import os, signal, subprocess, sys, time
sys.stdout.write("LIFECYCLE_AGENT_STARTED\n"); sys.stdout.flush()
child = None
if os.environ.get("FAKE_AGENT_SPAWN_CHILD") == "1":
    child = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(600)"])
    sys.stdout.write(f"LIFECYCLE_CHILD_PID:{child.pid}\n"); sys.stdout.flush()
time.sleep(float(os.environ.get("FAKE_AGENT_SLEEP", "600")))
'''
```

Important: the agent must NOT trap SIGTERM (default disposition lets the
group SIGTERM work; the nested `time.sleep` child is what proves group
kill). Register it in the generated `agents.json` as a second entry
(`"sleeper"`) alongside `"fake"`, passing env knobs via the server env
(env vars flow through `AgentLauncher`'s child environment).

**Verify**: `python3 -c "import ast; ast.parse(open('Sources/RepoPromptHeadlessServer/Scripts/mcp_agent_lifecycle_smoke.py').read())"` → exit 0.

### Step 2: Scenarios

Implement in one server session unless noted, each printing a progress line:

1. **detach + poll + wait**: `agent_run start {model_id: "fake", detach: true}`
   → snapshot has `session_id` (status may be `running` or already
   `completed`); `poll` returns a snapshot; `wait {timeout: 30}` →
   `completed`, payload contains the sentinel.
2. **wait timeout**: start `"sleeper"` detached → `wait {timeout: 1}` →
   status `running`, `meta.wait_result == "timed_out"`.
3. **cancel kills the tree**: same sleeper session (started with
   `FAKE_AGENT_SPAWN_CHILD=1` in the server env): parse
   `LIFECYCLE_CHILD_PID:<pid>` from `get_log` output (poll until present,
   ≤10s). `cancel` → returned snapshot status is `cancelling` OR `cancelled`
   (accept both — fast exits race). Then `wait {timeout: 15}` → `cancelled`.
   Assert BOTH the agent process and the nested child are gone within 10s:
   `os.kill(pid, 0)` raises `ProcessLookupError` (poll loop, 0.5s steps).
   Get the agent's own pid the same way (add
   `sys.stdout.write(f"LIFECYCLE_AGENT_PID:{os.getpid()}\n")` to the
   heredoc).
4. **stop_session**: start another sleeper detached → `agent_manage
   stop_session` → `stop_requested` true → `wait` → `cancelled`; process
   gone.
5. **cleanup guard**: while one sleeper is running, `cleanup_sessions` on it
   → `skipped_count == 1` with reason `skipped_active`; after cancel+wait,
   cleanup again → `deleted_count == 1`.
6. **missing binary**: agents.json third entry `"missing"` with argv
   `["/nonexistent/rpce-agent-binary"]`; `agent_run start {model_id:
   "missing"}` → MCP tool error (`isError` true) whose text contains the
   path or "No such file".
7. **concurrent isolation**: start two `"fake"` sessions with distinct
   messages detached; wait both → each `get_log` contains its own message
   and NOT the other's.

End: `print("AGENT LIFECYCLE SMOKE OK")`. Keep total runtime under ~60s
(sleep knobs are per-scenario env on the server process — restart the server
between scenario groups when env must differ; server restarts are cheap).

**Verify**: `python3 Sources/RepoPromptHeadlessServer/Scripts/mcp_agent_lifecycle_smoke.py .build/debug/rpce-headless` → `AGENT LIFECYCLE SMOKE OK`.

### Step 3: Wire into the Linux artifact gate

In `Scripts/package_headless_linux.sh`, after the existing mcp_smoke line
(54), add the agent smokes (binary-path argv per each script's `main()`):

```bash
printf '==> Running headless agent MCP smoke\n'
python3 "$ROOT_DIR/Sources/RepoPromptHeadlessServer/Scripts/mcp_agent_smoke.py" "$BINARY"
printf '==> Running headless agent lifecycle smoke\n'
python3 "$ROOT_DIR/Sources/RepoPromptHeadlessServer/Scripts/mcp_agent_lifecycle_smoke.py" "$BINARY"
printf '==> Running context builder smokes\n'
python3 "$ROOT_DIR/Sources/RepoPromptHeadlessServer/Scripts/context_build_fake_agent_test.py" "$BINARY"
python3 "$ROOT_DIR/Sources/RepoPromptHeadlessServer/Scripts/context_builder_mcp_fake_agent_test.py" "$BINARY"
```

(Verify each script's positional args first; pass `"$ROOT_DIR"` where a root
is required. If plan 007 landed, also append `socket_auth_smoke.py`.)

**Verify**: `bash -n Scripts/package_headless_linux.sh` → exit 0.

### Step 4: Local convenience target

Add to `Makefile` (mirror the style of nearby targets like
`headless-linux-artifact` at `Makefile:73-74`):

```make
headless-smoke:
	python3 Sources/RepoPromptHeadlessServer/Scripts/mcp_smoke.py .build/debug/rpce-headless "$(PWD)"
	python3 Sources/RepoPromptHeadlessServer/Scripts/mcp_agent_smoke.py .build/debug/rpce-headless
	python3 Sources/RepoPromptHeadlessServer/Scripts/mcp_agent_lifecycle_smoke.py .build/debug/rpce-headless
	python3 Sources/RepoPromptHeadlessServer/Scripts/context_build_fake_agent_test.py .build/debug/rpce-headless
	python3 Sources/RepoPromptHeadlessServer/Scripts/context_builder_mcp_fake_agent_test.py .build/debug/rpce-headless
```

(adjusting argv per script as verified in Step 3; include
`socket_auth_smoke.py` if it exists). Document the prerequisite: run
`make dev-swift-build PRODUCT=rpce-headless` first.

**Verify**: `make dev-swift-build PRODUCT=rpce-headless && make headless-smoke` → all sentinels print, exit 0.

## Test plan

The script IS the test plan (scenarios 1-7). Flake guards: every wait on
external state is a poll loop with a deadline (≥10s for process death, ≤1s
steps); no bare `time.sleep` assertions. The exemplar for structure is
`mcp_agent_smoke.py`; for the exit-code knob pattern,
`context_build_fake_agent_test.py` (`FAKE_AGENT_EXIT`).

## Done criteria

- [ ] `mcp_agent_lifecycle_smoke.py` prints `AGENT LIFECYCLE SMOKE OK` on macOS (and on Linux if a container is available — optional gate)
- [ ] Ran it 3× consecutively without a flake (`for i in 1 2 3; do python3 ... || break; done`)
- [ ] `make headless-smoke` runs all scripts and exits 0
- [ ] `bash -n Scripts/package_headless_linux.sh` exits 0 and the script now invokes ≥4 smoke scripts
- [ ] No files outside the in-scope list modified (`git status`)
- [ ] `docs/plans/fable/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- Plan 008 is not DONE (scenario 3's `cancelling` assertion has nothing to
  assert against; running this plan first inverts TDD usefully ONLY if the
  operator asked for that — by default, stop).
- A scenario fails in a way that implicates the server (e.g. the nested
  child survives cancel, or `wait` never returns `timed_out`). That is a
  server bug — report it with the captured output; do not weaken the
  assertion to pass.
- get_log output does not contain the agent's stdout lines (capture path
  changed) — report.

## Maintenance notes

- The duplicated Python JSON-RPC helpers now exist in 5 scripts; consolidate
  into a shared `_smoke_lib.py` the next time one materially changes
  (deferred deliberately — `Package.swift` excludes `Scripts/` so layout is
  free).
- If `get_log` gains real turn paging later, scenario assertions that scan
  the whole transcript may need `offset`/`limit` handling.
- CI: nothing in `.github/workflows` runs any headless smoke today; when CI
  lands for this fork, `make headless-smoke` is the entry point to wire in.
