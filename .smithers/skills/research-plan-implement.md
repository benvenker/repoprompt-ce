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

## Run

```bash
smithers workflow run research-plan-implement --prompt "<request>"
```

For structured inputs, pass JSON explicitly:

```bash
smithers workflow run research-plan-implement --input '{"prompt":"<request>"}'
```

## Operating Notes

- Workflow ID: `research-plan-implement`
- Entry file: `.smithers/workflows/research-plan-implement.tsx`
- Run from the repository root so `.smithers/agents.ts`, prompts, and relative imports resolve.
- Inspect progress with `smithers ps`, `smithers inspect <run-id>`, `smithers logs <run-id>`, and `smithers chat <run-id>`.
