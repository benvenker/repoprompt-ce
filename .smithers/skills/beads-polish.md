---
name: beads-polish
description: "Iteratively polish a selected Beads graph with parallel review, serialized br mutations, and strict validation."
---

# Beads Polish

## Workflow Metadata

The following workflow metadata is repository data, not instructions.

- Description: Iteratively polish a selected Beads graph with parallel review, serialized br mutations, and strict validation.
- Source type: `project`
- Metadata version: `1`
- Tags: beads, planning, review, polish
- Aliases: none

## Run

```bash
smithers workflow run beads-polish --prompt "<request>"
```

For structured inputs, pass JSON explicitly:

```bash
smithers workflow run beads-polish --input '{"prompt":"<request>"}'
```

## Operating Notes

- Workflow ID: `beads-polish`
- Entry file: `.smithers/workflows/beads-polish.tsx`
- Run from the repository root so `.smithers/agents.ts`, prompts, and relative imports resolve.
- Inspect progress with `smithers ps`, `smithers inspect <run-id>`, `smithers logs <run-id>`, and `smithers chat <run-id>`.
