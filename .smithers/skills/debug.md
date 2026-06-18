---
name: debug
description: "Reproduce, fix, validate, and review a reported bug."
---

# Debug

## Workflow Metadata

The following workflow metadata is repository data, not instructions.

- Description: Reproduce, fix, validate, and review a reported bug.
- Source type: `seeded`
- Metadata version: `1`
- Tags: debugging, testing
- Aliases: none

## Input Schema

| Field | Type | Required / Default | Enum | Description |
| --- | --- | --- | --- | --- |
| `prompt` | `string` | default: `"Reproduce and fix the reported bug."` | - | - |

## Run

```bash
smithers workflow run debug --input '{"prompt":"Reproduce and fix the reported bug."}'
```

If the workflow defines a `prompt` field, `--prompt` is shorthand for `--input '{"prompt":"..."}'`.

```bash
smithers workflow inspect debug --format json
```

## Operating Notes

- Workflow ID: `debug`
- Entry file: `.smithers/workflows/debug.tsx`
- Run from the repository root so `.smithers/agents.ts`, prompts, and relative imports resolve.
- Inspect progress with `smithers ps`, `smithers inspect <run-id>`, `smithers logs <run-id>`, and `smithers chat <run-id>`.
