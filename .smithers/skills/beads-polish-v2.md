---
name: beads-polish-v2
description: "Polish selected Beads with compact bead-local lanes, serialized per-bead apply, and explicit better-beads skill use."
---

# Beads Polish v2

## Workflow Metadata

The following workflow metadata is repository data, not instructions.

- Description: Polish selected Beads with compact bead-local lanes, serialized per-bead apply, and explicit better-beads skill use.
- Source type: `project`
- Metadata version: `1`
- Tags: beads, planning, review, polish
- Aliases: none

## Run

```bash
smithers workflow run beads-polish-v2 --prompt "<request>"
```

For structured inputs, pass JSON explicitly:

```bash
smithers workflow run beads-polish-v2 --input '{"prompt":"<request>"}'
```

## Operating Notes

- Workflow ID: `beads-polish-v2`
- Entry file: `.smithers/workflows/beads-polish-v2.tsx`
- Run from the repository root so `.smithers/agents.ts`, prompts, and relative imports resolve.
- Inspect progress with `smithers ps`, `smithers inspect <run-id>`, `smithers logs <run-id>`, and `smithers chat <run-id>`.
