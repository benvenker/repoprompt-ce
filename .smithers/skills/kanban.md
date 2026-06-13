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

## Run

```bash
smithers workflow run kanban --prompt "<request>"
```

For structured inputs, pass JSON explicitly:

```bash
smithers workflow run kanban --input '{"prompt":"<request>"}'
```

## Operating Notes

- Workflow ID: `kanban`
- Entry file: `.smithers/workflows/kanban.tsx`
- Run from the repository root so `.smithers/agents.ts`, prompts, and relative imports resolve.
- Inspect progress with `smithers ps`, `smithers inspect <run-id>`, `smithers logs <run-id>`, and `smithers chat <run-id>`.
