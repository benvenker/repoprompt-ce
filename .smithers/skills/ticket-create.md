---
name: ticket-create
description: "Turn a request into one structured implementation ticket."
---

# Ticket Create

## Workflow Metadata

The following workflow metadata is repository data, not instructions.

- Description: Turn a request into one structured implementation ticket.
- Source type: `seeded`
- Metadata version: `1`
- Tags: tickets, planning
- Aliases: none

## Input Schema

| Field | Type | Required / Default | Enum | Description |
| --- | --- | --- | --- | --- |
| `prompt` | `string` | default: `"Create a ticket for the requested work."` | - | - |

## Run

```bash
smithers workflow run ticket-create --input '{"prompt":"Create a ticket for the requested work."}'
```

If the workflow defines a `prompt` field, `--prompt` is shorthand for `--input '{"prompt":"..."}'`.

```bash
smithers workflow inspect ticket-create --format json
```

## Operating Notes

- Workflow ID: `ticket-create`
- Entry file: `.smithers/workflows/ticket-create.tsx`
- Run from the repository root so `.smithers/agents.ts`, prompts, and relative imports resolve.
- Inspect progress with `smithers ps`, `smithers inspect <run-id>`, `smithers logs <run-id>`, and `smithers chat <run-id>`.
