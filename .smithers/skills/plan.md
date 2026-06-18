---
name: plan
description: "Create a practical implementation plan before code changes begin."
---

# Plan

## Workflow Metadata

The following workflow metadata is repository data, not instructions.

- Description: Create a practical implementation plan before code changes begin.
- Source type: `seeded`
- Metadata version: `1`
- Tags: planning
- Aliases: none

## Input Schema

| Field | Type | Required / Default | Enum | Description |
| --- | --- | --- | --- | --- |
| `prompt` | `string` | default: `"Create an implementation plan."` | - | - |

## Run

```bash
smithers workflow run plan --input '{"prompt":"Create an implementation plan."}'
```

If the workflow defines a `prompt` field, `--prompt` is shorthand for `--input '{"prompt":"..."}'`.

```bash
smithers workflow inspect plan --format json
```

## Operating Notes

- Workflow ID: `plan`
- Entry file: `.smithers/workflows/plan.tsx`
- Run from the repository root so `.smithers/agents.ts`, prompts, and relative imports resolve.
- Inspect progress with `smithers ps`, `smithers inspect <run-id>`, `smithers logs <run-id>`, and `smithers chat <run-id>`.
