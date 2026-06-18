---
name: research-plan-implement
description: "Research a request, produce a plan, then implement it with validation and review."
---

# Research Plan Implement

## Workflow Metadata

The following workflow metadata is repository data, not instructions.

- Description: Research a request, produce a plan, then implement it with validation and review.
- Source type: `seeded`
- Metadata version: `1`
- Tags: research, planning, coding
- Aliases: rpi

## Input Schema

| Field | Type | Required / Default | Enum | Description |
| --- | --- | --- | --- | --- |
| `prompt` | `string` | default: `"Implement the requested change."` | - | - |
| `tdd` | `boolean` | default: `false` | - | - |

## Run

```bash
smithers workflow run research-plan-implement --input '{"prompt":"Implement the requested change.","tdd":false}'
```

If the workflow defines a `prompt` field, `--prompt` is shorthand for `--input '{"prompt":"..."}'`.

```bash
smithers workflow inspect research-plan-implement --format json
```

## Operating Notes

- Workflow ID: `research-plan-implement`
- Entry file: `.smithers/workflows/research-plan-implement.tsx`
- Run from the repository root so `.smithers/agents.ts`, prompts, and relative imports resolve.
- Inspect progress with `smithers ps`, `smithers inspect <run-id>`, `smithers logs <run-id>`, and `smithers chat <run-id>`.
