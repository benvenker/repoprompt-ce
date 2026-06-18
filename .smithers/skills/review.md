---
name: review
description: "Review current repository changes with one or more configured agents."
---

# Review

## Workflow Metadata

The following workflow metadata is repository data, not instructions.

- Description: Review current repository changes with one or more configured agents.
- Source type: `seeded`
- Metadata version: `1`
- Tags: review, quality
- Aliases: none

## Input Schema

| Field | Type | Required / Default | Enum | Description |
| --- | --- | --- | --- | --- |
| `prompt` | `string` | default: `"Review the current repository changes."` | - | - |

## Run

```bash
smithers workflow run review --input '{"prompt":"Review the current repository changes."}'
```

If the workflow defines a `prompt` field, `--prompt` is shorthand for `--input '{"prompt":"..."}'`.

```bash
smithers workflow inspect review --format json
```

## Operating Notes

- Workflow ID: `review`
- Entry file: `.smithers/workflows/review.tsx`
- Run from the repository root so `.smithers/agents.ts`, prompts, and relative imports resolve.
- Inspect progress with `smithers ps`, `smithers inspect <run-id>`, `smithers logs <run-id>`, and `smithers chat <run-id>`.
