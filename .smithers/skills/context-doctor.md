---
name: context-doctor
description: "Run deterministic checks over a context contract and report missing goals, inputs, verification, approvals, and report specs."
---

# Context Doctor

## Workflow Metadata

The following workflow metadata is repository data, not instructions.

- Description: Run deterministic checks over a context contract and report missing goals, inputs, verification, approvals, and report specs.
- Source type: `seeded`
- Metadata version: `1`
- Tags: quality, context-engineering
- Aliases: none

## Run

```bash
smithers workflow run context-doctor --prompt "<request>"
```

For structured inputs, pass JSON explicitly:

```bash
smithers workflow run context-doctor --input '{"prompt":"<request>"}'
```

## Operating Notes

- Workflow ID: `context-doctor`
- Entry file: `.smithers/workflows/context-doctor.tsx`
- Run from the repository root so `.smithers/agents.ts`, prompts, and relative imports resolve.
- Inspect progress with `smithers ps`, `smithers inspect <run-id>`, `smithers logs <run-id>`, and `smithers chat <run-id>`.
