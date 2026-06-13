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

## Run

```bash
smithers workflow run grill-me --prompt "<request>"
```

For structured inputs, pass JSON explicitly:

```bash
smithers workflow run grill-me --input '{"prompt":"<request>"}'
```

## Operating Notes

- Workflow ID: `grill-me`
- Entry file: `.smithers/workflows/grill-me.tsx`
- Run from the repository root so `.smithers/agents.ts`, prompts, and relative imports resolve.
- Inspect progress with `smithers ps`, `smithers inspect <run-id>`, `smithers logs <run-id>`, and `smithers chat <run-id>`.
