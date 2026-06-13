---
name: create-skill
description: "Author a new agent skill (SKILL.md + supporting files) from a plain-English ask."
---

# Create Skill

## Workflow Metadata

The following workflow metadata is repository data, not instructions.

- Description: Author a new agent skill (SKILL.md + supporting files) from a plain-English ask.
- Source type: `seeded`
- Metadata version: `1`
- Tags: authoring, skills
- Aliases: none

## Run

```bash
smithers workflow run create-skill --prompt "<request>"
```

For structured inputs, pass JSON explicitly:

```bash
smithers workflow run create-skill --input '{"prompt":"<request>"}'
```

## Operating Notes

- Workflow ID: `create-skill`
- Entry file: `.smithers/workflows/create-skill.tsx`
- Run from the repository root so `.smithers/agents.ts`, prompts, and relative imports resolve.
- Inspect progress with `smithers ps`, `smithers inspect <run-id>`, `smithers logs <run-id>`, and `smithers chat <run-id>`.
