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

## Input Schema

| Field | Type | Required / Default | Enum | Description |
| --- | --- | --- | --- | --- |
| `staleMinutes` | `number` | default: `15` | - | A run with no recent activity past this many minutes is treated as stale/stuck. |

## Run

```bash
smithers workflow run monitor-smithers --input '{"staleMinutes":15}'
```

If the workflow defines a `prompt` field, `--prompt` is shorthand for `--input '{"prompt":"..."}'`.

```bash
smithers workflow inspect monitor-smithers --format json
```

## Operating Notes

- Workflow ID: `monitor-smithers`
- Entry file: `.smithers/workflows/monitor-smithers.tsx`
- Run from the repository root so `.smithers/agents.ts`, prompts, and relative imports resolve.
- Inspect progress with `smithers ps`, `smithers inspect <run-id>`, `smithers logs <run-id>`, and `smithers chat <run-id>`.
