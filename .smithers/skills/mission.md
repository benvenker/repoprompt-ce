---
name: mission
description: "Run long-horizon work as approved milestones with focused workers and validation."
---

# Mission

## Workflow Metadata

The following workflow metadata is repository data, not instructions.

- Description: Run long-horizon work as approved milestones with focused workers and validation.
- Source type: `seeded`
- Metadata version: `1`
- Tags: planning, coding, validation
- Aliases: none

## Input Schema

| Field | Type | Required / Default | Enum | Description |
| --- | --- | --- | --- | --- |
| `prompt` | `string` | default: `"Describe the mission goal."` | - | - |
| `requirePlanApproval` | `boolean` | default: `true` | - | - |
| `maxMilestones` | `integer` | default: `6` | - | - |
| `maxFeaturesPerMilestone` | `integer` | default: `6` | - | - |
| `maxConcurrency` | `integer` | default: `3` | - | - |
| `useWorktrees` | `boolean` | default: `false` | - | - |
| `baseBranch` | `string` | default: `"main"` | - | - |

## Run

```bash
smithers workflow run mission --input '{"prompt":"Describe the mission goal.","requirePlanApproval":true,"maxMilestones":6,"maxFeaturesPerMilestone":6,"maxConcurrency":3,"useWorktrees":false,"baseBranch":"main"}'
```

If the workflow defines a `prompt` field, `--prompt` is shorthand for `--input '{"prompt":"..."}'`.

```bash
smithers workflow inspect mission --format json
```

## Operating Notes

- Workflow ID: `mission`
- Entry file: `.smithers/workflows/mission.tsx`
- Run from the repository root so `.smithers/agents.ts`, prompts, and relative imports resolve.
- Inspect progress with `smithers ps`, `smithers inspect <run-id>`, `smithers logs <run-id>`, and `smithers chat <run-id>`.
