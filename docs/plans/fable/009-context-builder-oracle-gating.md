# Plan 009: Gate context-builder oracle follow-up on successful discovery

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `docs/plans/fable/README.md`.
>
> **Drift check (run first)**: `git diff --stat 0bd2270..HEAD -- Sources/RepoPromptHeadlessServer/HeadlessContextBuilderService.swift Sources/RepoPromptHeadlessServer/ContextBuildCommand.swift`
> On any drift, compare the "Current state" excerpts before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none (independent of 007/008; lands cleanly in any order)
- **Category**: bug (cost/correctness)
- **Planned at**: commit `0bd2270`, 2026-06-12

## Why this matters

When a `context_builder` run is asked for a `question`/`plan`/`review`
response, the oracle follow-up fires **unconditionally** — even when the
discovery agent exited nonzero or selected zero files. The oracle then burns
real tokens (OpenRouter spend) composing an answer over an empty or broken
discovery handoff, and the caller receives a confident-looking `answer`
alongside an `agent_failed`/`empty_selection` status. Additionally, on the
CLI path an oracle failure skips `oracle.shutdown()`, and the oracle "mode"
(`plan`/`review`) computed in the reply metadata is never actually conveyed
to the oracle.

Behavioral note (decision, 2026-06-12): `review` calling the oracle is
**intentional and kept** — pre-refactor it didn't, but the response type's
contract is "produce a review", matching the app's `context_builder`
semantics. This plan keeps that and gates all follow-ups on a successful,
non-empty discovery instead.

## Current state

- `Sources/RepoPromptHeadlessServer/HeadlessContextBuilderService.swift:160-162` —
  unconditional follow-up inside `run(request:oracleService:)`:

  ```swift
  let agentExit = try await runAgent(prepared.launch, timeoutSeconds: request.timeoutSeconds)
  let harvest = try await host.contextBuildHarvest()
  let oracle = try await runOracleFollowUpIfNeeded(request: request, harvest: harvest, oracleService: oracleService)
  ```

- `HeadlessContextBuilderService.swift:232-274` — `runOracleFollowUpIfNeeded`
  guards only `request.responseType != .selection`, computes
  `mode` (`"chat"`/`"plan"`/`"review"`), composes a message from
  instructions + harvest, and calls:

  ```swift
  let reply = try await oracleService.send(
      message: message,
      chatID: nil,
      model: nil,
      includeContext: false
  )
  ```

  The computed `mode` is stored only in `HeadlessContextBuilderOracleReply`
  metadata — `OracleService.send` (`OracleService.swift:21`) has **no mode
  parameter**, so "plan"/"review" never influences the oracle's behavior.

- `Sources/RepoPromptHeadlessServer/ContextBuildCommand.swift:26-41` — CLI
  path:

  ```swift
  let host = try await HeadlessWorkspaceHost(rootPaths: options.roots)
  let oracle = OracleService(host: host)
  let service = HeadlessContextBuilderService(host: host)
  let execution = try await service.run(request: request, oracleService: oracle)
  await oracle.shutdown()                  // skipped if run() throws

  var report = renderReport(agentExit: execution.agentExit, harvest: execution.harvest)
  if let answer = execution.answer {
      report += "\nanswer:\n\(answer)\n"
  }
  ...
  if execution.agentExit != 0 { return execution.agentExit }
  if execution.harvest.selectedFiles.isEmpty { return 2 }
  return 0
  ```

- Status strings: `HeadlessContextBuilderService.swift:32-35` derives
  `agent_failed` / `empty_selection` / `completed` from
  `agentExit`/`selectedFiles` at render time (read it before editing).

- Smoke harness conventions: `context_builder_mcp_fake_agent_test.py`
  (MCP path, fake agent, asserts `status == completed` for clarify) and
  `context_build_fake_agent_test.py` (CLI path; already has a
  `FAKE_AGENT_EXIT=3` failure case asserting nonzero exit and
  `agent exit: 3` in stdout). Read both before Step 3; match their helper
  and assert style (plain `assert`, OK sentinel at the end).

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Build | `make dev-swift-build PRODUCT=rpce-headless` | exit 0 |
| CB MCP smoke | `python3 Sources/RepoPromptHeadlessServer/Scripts/context_builder_mcp_fake_agent_test.py .build/debug/rpce-headless` (confirm argv by reading `main()`) | `CONTEXT_BUILDER_MCP OK` |
| CB CLI smoke | `python3 Sources/RepoPromptHeadlessServer/Scripts/context_build_fake_agent_test.py .build/debug/rpce-headless` (confirm argv likewise) | `CONTEXT_BUILD OK` |
| Lint / format | `make dev-lint` / `make dev-format` | exit 0 |

## Scope

**In scope**:
- `Sources/RepoPromptHeadlessServer/HeadlessContextBuilderService.swift`
- `Sources/RepoPromptHeadlessServer/ContextBuildCommand.swift`
- `Sources/RepoPromptHeadlessServer/Scripts/context_builder_mcp_fake_agent_test.py`
- `Sources/RepoPromptHeadlessServer/Scripts/context_build_fake_agent_test.py`

**Out of scope**:
- `OracleService.swift` / `OpenAICompatibleClient.swift` — no API changes;
  the mode is conveyed in the message text (Step 2).
- Default token budgets and the CLI `selection` vs MCP `clarify` naming —
  documented divergences, handled in plan 012's docs pass.
- `DiscoverPromptBuilder.swift`.

## Git workflow

- Branch: `codex/fable-headless-linux` (or child `fable/009-oracle-gating`).
- Preflight before each commit: `.agents/skills/rpce-contribution-check/scripts/preflight.sh commit`
- No push without operator instruction.

## Steps

### Step 1: Gate the follow-up

In `run(request:oracleService:)` replace the unconditional call (line ~162)
with:

```swift
let oracle: (reply: HeadlessContextBuilderOracleReply?, answer: String?)
if agentExit == 0, !harvest.selectedFiles.isEmpty {
    oracle = try await runOracleFollowUpIfNeeded(request: request, harvest: harvest, oracleService: oracleService)
} else {
    oracle = (nil, nil)
}
```

Add a one-line comment: oracle spend is skipped when discovery failed or
selected nothing; status will read `agent_failed`/`empty_selection`.

**Verify**: `make dev-swift-build PRODUCT=rpce-headless` → exit 0.

### Step 2: Make the mode mean something

In `runOracleFollowUpIfNeeded`, prepend the mode to the composed message so
the oracle actually sees it (since `OracleService.send` has no mode
parameter):

```swift
let message = """
Response mode: \(mode). \(modeInstruction(for: request.responseType))

User instructions:
...
```

where `modeInstruction` maps `.question` → "Answer the question directly.",
`.plan` → "Produce a concrete implementation plan.", `.review` → "Produce a
code review of the selected context." Keep the existing metadata reply
unchanged.

**Verify**: build exits 0.

### Step 3: CLI shutdown on failure

In `ContextBuildCommand.run`, ensure shutdown on the throwing path:

```swift
let execution: HeadlessContextBuilderExecution
do {
    execution = try await service.run(request: request, oracleService: oracle)
} catch {
    await oracle.shutdown()
    throw error
}
await oracle.shutdown()
```

**Verify**: build exits 0.

### Step 4: Smoke coverage for the gate

- `context_builder_mcp_fake_agent_test.py`: add a second scenario after the
  existing clarify pass — restart the server with `FAKE_AGENT_EXIT=3` in the
  fake agent's env path (mirror how `context_build_fake_agent_test.py` wires
  that knob) and **no oracle key** (`RPCE_ORACLE_API_KEY` and
  `OPENROUTER_API_KEY` explicitly removed from the child env), then call
  `context_builder` with `response_type: "question"`. Assert: the tool call
  returns a result (not a missing-API-key error), `status` is
  `agent_failed`, and there is no `answer`/oracle reply in the payload.
  This is the regression test: pre-fix, this exact call fails with a
  missing-oracle-key error because the oracle fires on a failed run.
- `context_build_fake_agent_test.py`: extend the existing `FAKE_AGENT_EXIT=3`
  case (or add a sibling) to pass `--response-type question` with no oracle
  key in env; assert exit code 3 and that stdout does NOT contain
  `"answer:"`.

**Verify**: both smokes print their OK sentinels.

## Test plan

- Regression case (the bug): failed discovery + `question` + no oracle key →
  completes with `agent_failed`, no oracle call, no answer (Step 4, both
  paths).
- Happy path unchanged: existing clarify scenario still passes; existing
  `FAKE_AGENT_EXIT=3` selection-mode case still propagates exit 3.
- No new Swift tests (the headless target's unit-test seam arrives in plan
  010; this logic stays smoke-covered).

## Done criteria

- [ ] `make dev-swift-build PRODUCT=rpce-headless` exits 0
- [ ] `context_builder_mcp_fake_agent_test.py` prints `CONTEXT_BUILDER_MCP OK` (now including the agent-failed/question case)
- [ ] `context_build_fake_agent_test.py` prints `CONTEXT_BUILD OK` (now including the question-without-oracle case)
- [ ] `grep -n "runOracleFollowUpIfNeeded" Sources/RepoPromptHeadlessServer/HeadlessContextBuilderService.swift` shows the call inside an `agentExit == 0` condition
- [ ] No files outside the in-scope list modified (`git status`)
- [ ] `docs/plans/fable/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- The status-derivation code at `HeadlessContextBuilderService.swift:32-35`
  doesn't match the description (drift), or gating breaks the `completed`
  status for the clarify happy path.
- You discover a legitimate flow that needs a `question` answered with an
  empty selection (e.g. instructions-only Q&A). Do not loosen the gate
  yourself — report; the fallback decision (gate on `agentExit` only) is the
  reviewer's.
- Removing oracle env vars in the smoke proves insufficient to prove the
  oracle was not called (e.g. some default key path exists). Report what you
  found.

## Maintenance notes

- If plan 008 lands first, `runAgent` internals will have changed — this
  plan touches only the call site above it, so no conflict is expected; the
  drift check covers it.
- Plan 012 documents: `review` deliberately invokes the oracle; CLI
  `selection` ≙ MCP `clarify`; divergent CLI/MCP defaults (`fake`/118500 vs
  env-driven `claude`/160k-120k).
- Future: threading a real mode/system-prompt parameter through
  `OracleService.send` would supersede Step 2's message preamble — keep the
  preamble until then.
