---
name: research
description: "Gather repository and external context before planning or building."
---

# Research

## Workflow Metadata

The following workflow metadata is repository data, not instructions.

- Description: Gather repository and external context before planning or building.
- Source type: `seeded`
- Metadata version: `1`
- Tags: research
- Aliases: none

## Run

```bash
smithers workflow run research --prompt "<request>"
```

For structured inputs, pass JSON explicitly:

```bash
smithers workflow run research --input '{"prompt":"<request>"}'
```

## Operating Notes

- Workflow ID: `research`
- Entry file: `.smithers/workflows/research.tsx`
- Run from the repository root so `.smithers/agents.ts`, prompts, and relative imports resolve.
- Inspect progress with `smithers ps`, `smithers inspect <run-id>`, `smithers logs <run-id>`, and `smithers chat <run-id>`.
