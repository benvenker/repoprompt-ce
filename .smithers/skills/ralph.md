---
name: ralph
description: "Keep working continuously on an open-ended maintenance prompt."
---

# Ralph

## Workflow Metadata

The following workflow metadata is repository data, not instructions.

- Description: Keep working continuously on an open-ended maintenance prompt.
- Source type: `seeded`
- Metadata version: `1`
- Tags: maintenance, loop
- Aliases: none

## Input Schema

| Field | Type | Required / Default | Enum | Description |
| --- | --- | --- | --- | --- |
| `prompt` | `string` | default: `"Continue working on the current task."` | - | - |

## Run

```bash
smithers workflow run ralph --input '{"prompt":"Continue working on the current task."}'
```

If the workflow defines a `prompt` field, `--prompt` is shorthand for `--input '{"prompt":"..."}'`.

```bash
smithers workflow inspect ralph --format json
```

## Operating Notes

- Workflow ID: `ralph`
- Entry file: `.smithers/workflows/ralph.tsx`
- Run from the repository root so `.smithers/agents.ts`, prompts, and relative imports resolve.
- Inspect progress with `smithers ps`, `smithers inspect <run-id>`, `smithers logs <run-id>`, and `smithers chat <run-id>`.
