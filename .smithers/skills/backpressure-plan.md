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

## Run

```bash
smithers workflow run backpressure-plan --prompt "<request>"
```

For structured inputs, pass JSON explicitly:

```bash
smithers workflow run backpressure-plan --input '{"prompt":"<request>"}'
```

## Operating Notes

- Workflow ID: `backpressure-plan`
- Entry file: `.smithers/workflows/backpressure-plan.tsx`
- Run from the repository root so `.smithers/agents.ts`, prompts, and relative imports resolve.
- Inspect progress with `smithers ps`, `smithers inspect <run-id>`, `smithers logs <run-id>`, and `smithers chat <run-id>`.
