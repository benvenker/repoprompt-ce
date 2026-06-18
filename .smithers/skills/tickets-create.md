---
name: tickets-create
description: "Break a larger request into multiple implementable tickets."
---

# Tickets Create

## Workflow Metadata

The following workflow metadata is repository data, not instructions.

- Description: Break a larger request into multiple implementable tickets.
- Source type: `seeded`
- Metadata version: `1`
- Tags: tickets, planning
- Aliases: none

## Input Schema

| Field | Type | Required / Default | Enum | Description |
| --- | --- | --- | --- | --- |
| `prompt` | `string` | default: `"Create tickets for the requested work."` | - | - |

## Run

```bash
smithers workflow run tickets-create --input '{"prompt":"Create tickets for the requested work."}'
```

If the workflow defines a `prompt` field, `--prompt` is shorthand for `--input '{"prompt":"..."}'`.

```bash
smithers workflow inspect tickets-create --format json
```

## Operating Notes

- Workflow ID: `tickets-create`
- Entry file: `.smithers/workflows/tickets-create.tsx`
- Run from the repository root so `.smithers/agents.ts`, prompts, and relative imports resolve.
- Inspect progress with `smithers ps`, `smithers inspect <run-id>`, `smithers logs <run-id>`, and `smithers chat <run-id>`.
