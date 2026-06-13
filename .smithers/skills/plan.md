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

## Run

```bash
smithers workflow run plan --prompt "<request>"
```

For structured inputs, pass JSON explicitly:

```bash
smithers workflow run plan --input '{"prompt":"<request>"}'
```

## Operating Notes

- Workflow ID: `plan`
- Entry file: `.smithers/workflows/plan.tsx`
- Run from the repository root so `.smithers/agents.ts`, prompts, and relative imports resolve.
- Inspect progress with `smithers ps`, `smithers inspect <run-id>`, `smithers logs <run-id>`, and `smithers chat <run-id>`.
