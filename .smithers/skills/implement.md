---
name: implement
description: "Implement a focused change with validation and review feedback loops."
---

# Implement

## Workflow Metadata

The following workflow metadata is repository data, not instructions.

- Description: Implement a focused change with validation and review feedback loops.
- Source type: `seeded`
- Metadata version: `1`
- Tags: coding, implementation, review
- Aliases: none

## Run

```bash
smithers workflow run implement --prompt "<request>"
```

For structured inputs, pass JSON explicitly:

```bash
smithers workflow run implement --input '{"prompt":"<request>"}'
```

## Operating Notes

- Workflow ID: `implement`
- Entry file: `.smithers/workflows/implement.tsx`
- Run from the repository root so `.smithers/agents.ts`, prompts, and relative imports resolve.
- Inspect progress with `smithers ps`, `smithers inspect <run-id>`, `smithers logs <run-id>`, and `smithers chat <run-id>`.
