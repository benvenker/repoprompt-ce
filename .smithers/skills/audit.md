---
name: audit
description: "Audit feature groups for tests, docs, observability, and maintainability gaps."
---

# Audit

## Workflow Metadata

The following workflow metadata is repository data, not instructions.

- Description: Audit feature groups for tests, docs, observability, and maintainability gaps.
- Source type: `seeded`
- Metadata version: `1`
- Tags: audit, quality
- Aliases: none

## Run

```bash
smithers workflow run audit --prompt "<request>"
```

For structured inputs, pass JSON explicitly:

```bash
smithers workflow run audit --input '{"prompt":"<request>"}'
```

## Operating Notes

- Workflow ID: `audit`
- Entry file: `.smithers/workflows/audit.tsx`
- Run from the repository root so `.smithers/agents.ts`, prompts, and relative imports resolve.
- Inspect progress with `smithers ps`, `smithers inspect <run-id>`, `smithers logs <run-id>`, and `smithers chat <run-id>`.
