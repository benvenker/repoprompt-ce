---
name: backpressure-plan
description: "Turn acceptance criteria into a gate matrix (schema/test/eval/review/approval/trace) so a workflow cannot just try-its-best and move on."
---

# Backpressure Plan

## Workflow Metadata

The following workflow metadata is repository data, not instructions.

- Description: Turn acceptance criteria into a gate matrix (schema/test/eval/review/approval/trace) so a workflow cannot just try-its-best and move on.
- Source type: `seeded`
- Metadata version: `1`
- Tags: quality, backpressure
- Aliases: none

## Input Schema

| Field | Type | Required / Default | Enum | Description |
| --- | --- | --- | --- | --- |
| `prompt` | `string` | default: `"Describe the goal and its acceptance criteria in plain English."` | - | The goal / acceptance criteria to turn into a backpressure gate matrix. |

## Run

```bash
smithers workflow run backpressure-plan --input '{"prompt":"Describe the goal and its acceptance criteria in plain English."}'
```

If the workflow defines a `prompt` field, `--prompt` is shorthand for `--input '{"prompt":"..."}'`.

```bash
smithers workflow inspect backpressure-plan --format json
```

## Operating Notes

- Workflow ID: `backpressure-plan`
- Entry file: `.smithers/workflows/backpressure-plan.tsx`
- Run from the repository root so `.smithers/agents.ts`, prompts, and relative imports resolve.
- Inspect progress with `smithers ps`, `smithers inspect <run-id>`, `smithers logs <run-id>`, and `smithers chat <run-id>`.
