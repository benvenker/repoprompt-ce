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

## Run

```bash
smithers workflow run ticket-create --prompt "<request>"
```

For structured inputs, pass JSON explicitly:

```bash
smithers workflow run ticket-create --input '{"prompt":"<request>"}'
```

## Operating Notes

- Workflow ID: `ticket-create`
- Entry file: `.smithers/workflows/ticket-create.tsx`
- Run from the repository root so `.smithers/agents.ts`, prompts, and relative imports resolve.
- Inspect progress with `smithers ps`, `smithers inspect <run-id>`, `smithers logs <run-id>`, and `smithers chat <run-id>`.
