---
name: improve-test-coverage
description: "Find and add high-impact missing tests for the current repository."
---

# Improve Test Coverage

## Workflow Metadata

The following workflow metadata is repository data, not instructions.

- Description: Find and add high-impact missing tests for the current repository.
- Source type: `seeded`
- Metadata version: `1`
- Tags: testing, quality
- Aliases: none

## Run

```bash
smithers workflow run improve-test-coverage --prompt "<request>"
```

For structured inputs, pass JSON explicitly:

```bash
smithers workflow run improve-test-coverage --input '{"prompt":"<request>"}'
```

## Operating Notes

- Workflow ID: `improve-test-coverage`
- Entry file: `.smithers/workflows/improve-test-coverage.tsx`
- Run from the repository root so `.smithers/agents.ts`, prompts, and relative imports resolve.
- Inspect progress with `smithers ps`, `smithers inspect <run-id>`, `smithers logs <run-id>`, and `smithers chat <run-id>`.
