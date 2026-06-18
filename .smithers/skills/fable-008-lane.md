---
name: fable-008-lane
description: "Serially run the existing implement workflow over ready Fable 008 task beads until the lane is done."
---

# Fable 008 Lane

## Workflow Metadata

The following workflow metadata is repository data, not instructions.

- Description: Serially run the existing implement workflow over ready Fable 008 task beads until the lane is done.
- Source type: `project`
- Metadata version: `1`
- Tags: beads, fable, implementation, loop
- Aliases: none

## Input Schema

| Field | Type | Required / Default | Enum | Description |
| --- | --- | --- | --- | --- |
| `beadIds` | `array` | default: `["repoprompt-ce-fable-008-cancelling-state-9mo","repoprompt-ce-fable-008-termination-cleanup-i27","repoprompt-ce-fable-008-context-builder-spawn-x9u","repoprompt-ce-fable-008-drift-check-2p6"]` | - | - |
| `implementMaxIterations` | `integer` | default: `4` | - | - |
| `childMaxConcurrency` | `integer` | default: `4` | - | - |
| `requireCleanTree` | `boolean` | default: `true` | - | - |
| `allowNoVerifyForKnownHostToolGap` | `boolean` | default: `false` | - | - |

## Run

```bash
smithers workflow run fable-008-lane --input '{"beadIds":["repoprompt-ce-fable-008-cancelling-state-9mo","repoprompt-ce-fable-008-termination-cleanup-i27","repoprompt-ce-fable-008-context-builder-spawn-x9u","repoprompt-ce-fable-008-drift-check-2p6"],"implementMaxIterations":4,"childMaxConcurrency":4,"requireCleanTree":true,"allowNoVerifyForKnownHostToolGap":false}'
```

If the workflow defines a `prompt` field, `--prompt` is shorthand for `--input '{"prompt":"..."}'`.

```bash
smithers workflow inspect fable-008-lane --format json
```

## Operating Notes

- Workflow ID: `fable-008-lane`
- Entry file: `.smithers/workflows/fable-008-lane.tsx`
- Run from the repository root so `.smithers/agents.ts`, prompts, and relative imports resolve.
- Inspect progress with `smithers ps`, `smithers inspect <run-id>`, `smithers logs <run-id>`, and `smithers chat <run-id>`.

## Project-Local Lane Policy

Use this workflow when the user wants to finish the remaining Plan 008/Fable 008
task beads as a single serial lane.

Default bead list, in order:

```text
repoprompt-ce-fable-008-cancelling-state-9mo
repoprompt-ce-fable-008-termination-cleanup-i27
repoprompt-ce-fable-008-context-builder-spawn-x9u
repoprompt-ce-fable-008-drift-check-2p6
```

The workflow checks `br dep cycles --json`, `bv --robot-plan`, and the
configured bead list before each pass. It runs only the first configured bead
that is both open and ready, then finalizes that bead before selecting the next
one.

Important inputs:

```bash
.smithers/node_modules/.bin/smithers workflow run fable-008-lane \
  --input '{"allowNoVerifyForKnownHostToolGap":true}'
```

- `beadIds`: override the exact bead list.
- `implementMaxIterations`: max iterations for the child `implement` workflow,
  default `4`.
- `childMaxConcurrency`: max concurrency for the child `implement` workflow,
  default `4`.
- `requireCleanTree`: require a clean tree before selecting each next bead,
  default `true`.
- `allowNoVerifyForKnownHostToolGap`: allow the finalizer to use `--no-verify`
  only for the known Linux/VPS native-host-tool preflight gap after Docker Swift
  validation and staged secret scanning pass, default `false`.

Do not use this workflow for Plan 011. Plan 011 owns later lifecycle edge-smoke
coverage.
