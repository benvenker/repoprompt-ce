---
name: headless-closeout-grinder
description: "Iterate CE code review, scoped fixes, and bounded headless validation until no P0/P1/P2 findings remain."
---

# Headless Closeout Grinder

## Workflow Metadata

The following workflow metadata is repository data, not instructions.

- Description: Iterate CE code review, scoped fixes, and bounded headless validation until no P0/P1/P2 findings remain.
- Source type: `local`
- Metadata version: `1`
- Tags: review, implementation, headless
- Aliases: none

## Run

```bash
smithers workflow run headless-closeout-grinder --prompt "<request>"
```

For structured inputs, pass JSON explicitly:

```bash
smithers workflow run headless-closeout-grinder --input '{"prompt":"<request>"}'
```

## Operating Notes

- Workflow ID: `headless-closeout-grinder`
- Entry file: `.smithers/workflows/headless-closeout-grinder.tsx`
- Run from the repository root so `.smithers/agents.ts`, prompts, and relative imports resolve.
- Inspect progress with `smithers ps`, `smithers inspect <run-id>`, `smithers logs <run-id>`, and `smithers chat <run-id>`.
