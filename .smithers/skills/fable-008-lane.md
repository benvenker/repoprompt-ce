---
name: fable-008-lane
description: "Serially run the existing implement workflow over the configured Fable 008 task beads until they are closed."
---

# Fable 008 Lane

Use this workflow when the user wants to finish the remaining Plan 008/Fable 008 task beads as a single serial lane.

Run from the repository root:

```bash
.smithers/node_modules/.bin/smithers workflow run fable-008-lane
```

Default bead list, in order:

```text
repoprompt-ce-fable-008-cancelling-state-9mo
repoprompt-ce-fable-008-termination-cleanup-i27
repoprompt-ce-fable-008-context-builder-spawn-x9u
repoprompt-ce-fable-008-drift-check-2p6
```

The workflow checks `br dep cycles --json`, `bv --robot-plan`, and the configured bead list before each pass. It runs only the first configured bead that is both open and ready, then finalizes that bead before selecting the next one.

Important inputs:

```bash
.smithers/node_modules/.bin/smithers workflow run fable-008-lane \
  --input '{"allowNoVerifyForKnownHostToolGap":true}'
```

- `beadIds`: override the exact bead list.
- `implementMaxIterations`: max iterations for the child `implement` workflow, default `4`.
- `childMaxConcurrency`: max concurrency for the child `implement` workflow, default `4`.
- `requireCleanTree`: require a clean tree before selecting each next bead, default `true`.
- `allowNoVerifyForKnownHostToolGap`: allow the finalizer to use `--no-verify` only for the known Linux/VPS native-host-tool preflight gap after Docker Swift validation and staged secret scanning pass, default `false`.

Do not use this workflow for Plan 011. Plan 011 owns later lifecycle edge-smoke coverage.
