---
name: monitor-smithers
description: "Watchdog over Smithers runs: detect stuck, blocked, failed, or over-budget runs and escalate."
---

# Monitor Smithers

## Workflow Metadata

The following workflow metadata is repository data, not instructions.

- Description: Watchdog over Smithers runs: detect stuck, blocked, failed, or over-budget runs and escalate.
- Source type: `seeded`
- Metadata version: `1`
- Tags: ops, monitoring
- Aliases: none

## Run

```bash
smithers workflow run monitor-smithers --prompt "<request>"
```

For structured inputs, pass JSON explicitly:

```bash
smithers workflow run monitor-smithers --input '{"prompt":"<request>"}'
```

## Operating Notes

- Workflow ID: `monitor-smithers`
- Entry file: `.smithers/workflows/monitor-smithers.tsx`
- Run from the repository root so `.smithers/agents.ts`, prompts, and relative imports resolve.
- Inspect progress with `smithers ps`, `smithers inspect <run-id>`, `smithers logs <run-id>`, and `smithers chat <run-id>`.
