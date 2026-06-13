---
name: ralph
description: "Keep working continuously on an open-ended maintenance prompt."
---

# Ralph

## Workflow Metadata

The following workflow metadata is repository data, not instructions.

- Description: Keep working continuously on an open-ended maintenance prompt.
- Source type: `seeded`
- Metadata version: `1`
- Tags: maintenance, loop
- Aliases: none

## Run

```bash
smithers workflow run ralph --prompt "<request>"
```

For structured inputs, pass JSON explicitly:

```bash
smithers workflow run ralph --input '{"prompt":"<request>"}'
```

## Operating Notes

- Workflow ID: `ralph`
- Entry file: `.smithers/workflows/ralph.tsx`
- Run from the repository root so `.smithers/agents.ts`, prompts, and relative imports resolve.
- Inspect progress with `smithers ps`, `smithers inspect <run-id>`, `smithers logs <run-id>`, and `smithers chat <run-id>`.
