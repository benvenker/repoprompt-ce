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

## Input Schema

| Field | Type | Required / Default | Enum | Description |
| --- | --- | --- | --- | --- |
| `prompt` | `string` | default: `"Describe the agent skill you want to create, in plain English."` | - | Plain-English description of the agent skill you want Smithers to author. |
| `name` | `string | null` | default: `null` | - | Desired kebab-case skill id. Null lets the clarify/design steps choose one. |
| `review` | `boolean` | default: `true` | - | Pause for human approval of the design before any files are written. |

## Run

```bash
smithers workflow run create-skill --input '{"prompt":"Describe the agent skill you want to create, in plain English.","name":null,"review":true}'
```

If the workflow defines a `prompt` field, `--prompt` is shorthand for `--input '{"prompt":"..."}'`.

```bash
smithers workflow inspect create-skill --format json
```

## Operating Notes

- Workflow ID: `create-skill`
- Entry file: `.smithers/workflows/create-skill.tsx`
- Run from the repository root so `.smithers/agents.ts`, prompts, and relative imports resolve.
- Inspect progress with `smithers ps`, `smithers inspect <run-id>`, `smithers logs <run-id>`, and `smithers chat <run-id>`.
