---
name: extract-skill
description: "After a run, harvest a reusable skill or workflow and durable memory from the pattern."
---

# Extract Skill

## Workflow Metadata

The following workflow metadata is repository data, not instructions.

- Description: After a run, harvest a reusable skill or workflow and durable memory from the pattern.
- Source type: `seeded`
- Metadata version: `1`
- Tags: reuse, skills, memory
- Aliases: none

## Run

```bash
smithers workflow run extract-skill --prompt "<request>"
```

For structured inputs, pass JSON explicitly:

```bash
smithers workflow run extract-skill --input '{"prompt":"<request>"}'
```

## Operating Notes

- Workflow ID: `extract-skill`
- Entry file: `.smithers/workflows/extract-skill.tsx`
- Run from the repository root so `.smithers/agents.ts`, prompts, and relative imports resolve.
- Inspect progress with `smithers ps`, `smithers inspect <run-id>`, `smithers logs <run-id>`, and `smithers chat <run-id>`.
