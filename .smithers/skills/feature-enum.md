---
name: feature-enum
description: "Build or refine a code-backed feature inventory for a repository."
---

# Feature Enum

## Workflow Metadata

The following workflow metadata is repository data, not instructions.

- Description: Build or refine a code-backed feature inventory for a repository.
- Source type: `seeded`
- Metadata version: `1`
- Tags: audit, inventory
- Aliases: none

## Run

```bash
smithers workflow run feature-enum --prompt "<request>"
```

For structured inputs, pass JSON explicitly:

```bash
smithers workflow run feature-enum --input '{"prompt":"<request>"}'
```

## Operating Notes

- Workflow ID: `feature-enum`
- Entry file: `.smithers/workflows/feature-enum.tsx`
- Run from the repository root so `.smithers/agents.ts`, prompts, and relative imports resolve.
- Inspect progress with `smithers ps`, `smithers inspect <run-id>`, `smithers logs <run-id>`, and `smithers chat <run-id>`.
