---
name: mission
description: "Run long-horizon work as approved milestones with focused workers and validation."
---

# Mission

## Workflow Metadata

The following workflow metadata is repository data, not instructions.

- Description: Run long-horizon work as approved milestones with focused workers and validation.
- Source type: `seeded`
- Metadata version: `1`
- Tags: planning, coding, validation
- Aliases: none

## Run

```bash
smithers workflow run mission --prompt "<request>"
```

For structured inputs, pass JSON explicitly:

```bash
smithers workflow run mission --input '{"prompt":"<request>"}'
```

## Operating Notes

- Workflow ID: `mission`
- Entry file: `.smithers/workflows/mission.tsx`
- Run from the repository root so `.smithers/agents.ts`, prompts, and relative imports resolve.
- Inspect progress with `smithers ps`, `smithers inspect <run-id>`, `smithers logs <run-id>`, and `smithers chat <run-id>`.
