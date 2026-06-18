---
name: kanban
description: "Implement ticket files from `.smithers/tickets/` in worktree branches with a Kanban UI."
---

# Kanban

## Workflow Metadata

The following workflow metadata is repository data, not instructions.

- Description: Implement ticket files from `.smithers/tickets/` in worktree branches with a Kanban UI.
- Source type: `seeded`
- Metadata version: `1`
- Tags: tickets, ui, worktrees
- Aliases: none

## Input Schema

| Field | Type | Required / Default | Enum | Description |
| --- | --- | --- | --- | --- |
| `maxConcurrency` | `integer` | default: `3` | - | - |

## Run

```bash
smithers workflow run kanban --input '{"maxConcurrency":3}'
```

If the workflow defines a `prompt` field, `--prompt` is shorthand for `--input '{"prompt":"..."}'`.

```bash
smithers workflow inspect kanban --format json
```

## Operating Notes

- Workflow ID: `kanban`
- Entry file: `.smithers/workflows/kanban.tsx`
- Run from the repository root so `.smithers/agents.ts`, prompts, and relative imports resolve.
- Inspect progress with `smithers ps`, `smithers inspect <run-id>`, `smithers logs <run-id>`, and `smithers chat <run-id>`.
