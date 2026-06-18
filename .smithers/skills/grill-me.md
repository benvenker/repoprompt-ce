---
name: grill-me
description: "Ask targeted questions until vague requirements become actionable."
---

# Grill Me

## Workflow Metadata

The following workflow metadata is repository data, not instructions.

- Description: Ask targeted questions until vague requirements become actionable.
- Source type: `seeded`
- Metadata version: `1`
- Tags: requirements, planning
- Aliases: none

## Input Schema

| Field | Type | Required / Default | Enum | Description |
| --- | --- | --- | --- | --- |
| `prompt` | `string` | default: `"Describe what you want to get grilled on."` | - | - |
| `maxIterations` | `integer` | default: `30` | - | - |

## Run

```bash
smithers workflow run grill-me --input '{"prompt":"Describe what you want to get grilled on.","maxIterations":30}'
```

If the workflow defines a `prompt` field, `--prompt` is shorthand for `--input '{"prompt":"..."}'`.

```bash
smithers workflow inspect grill-me --format json
```

## Operating Notes

- Workflow ID: `grill-me`
- Entry file: `.smithers/workflows/grill-me.tsx`
- Run from the repository root so `.smithers/agents.ts`, prompts, and relative imports resolve.
- Inspect progress with `smithers ps`, `smithers inspect <run-id>`, `smithers logs <run-id>`, and `smithers chat <run-id>`.
