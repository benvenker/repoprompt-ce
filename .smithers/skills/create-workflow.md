---
name: create-workflow
description: "Build a new Smithers workflow from a plain-English ask — clarify, provision docs & skills, design, scaffold, verify, and document."
---

# Create Workflow

## Workflow Metadata

The following workflow metadata is repository data, not instructions.

- Description: Build a new Smithers workflow from a plain-English ask — clarify, provision docs & skills, design, scaffold, verify, and document.
- Source type: `seeded`
- Metadata version: `1`
- Tags: authoring, workflow-pack, scaffolding
- Aliases: none

## Run

```bash
smithers workflow run create-workflow --prompt "<request>"
```

For structured inputs, pass JSON explicitly:

```bash
smithers workflow run create-workflow --input '{"prompt":"<request>"}'
```

## Operating Notes

- Workflow ID: `create-workflow`
- Entry file: `.smithers/workflows/create-workflow.tsx`
- Run from the repository root so `.smithers/agents.ts`, prompts, and relative imports resolve.
- Inspect progress with `smithers ps`, `smithers inspect <run-id>`, `smithers logs <run-id>`, and `smithers chat <run-id>`.
