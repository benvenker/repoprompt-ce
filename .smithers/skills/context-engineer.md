---
name: context-engineer
description: "Turn a vague user script into a context contract, route it to skills/workflows, add backpressure, execute, and report — the concierge proxy."
---

# Context Engineer

## Workflow Metadata

The following workflow metadata is repository data, not instructions.

- Description: Turn a vague user script into a context contract, route it to skills/workflows, add backpressure, execute, and report — the concierge proxy.
- Source type: `seeded`
- Metadata version: `1`
- Tags: concierge, context-engineering, planning
- Aliases: none

## Run

```bash
smithers workflow run context-engineer --prompt "<request>"
```

For structured inputs, pass JSON explicitly:

```bash
smithers workflow run context-engineer --input '{"prompt":"<request>"}'
```

## Operating Notes

- Workflow ID: `context-engineer`
- Entry file: `.smithers/workflows/context-engineer.tsx`
- Run from the repository root so `.smithers/agents.ts`, prompts, and relative imports resolve.
- Inspect progress with `smithers ps`, `smithers inspect <run-id>`, `smithers logs <run-id>`, and `smithers chat <run-id>`.
