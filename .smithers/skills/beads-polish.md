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

## Input Schema

| Field | Type | Required / Default | Enum | Description |
| --- | --- | --- | --- | --- |
| `selector` | `string` | default: `"plan"` | `plan`, `ids`, `label`, `query`, `ready`, `all` | - |
| `planPath` | `string | null` | default: `"docs/plans/fable/007-full-tool-socket-auth.md"` | - | - |
| `beadIds` | `array` | default: `[]` | - | - |
| `label` | `string | null` | default: `null` | - | - |
| `query` | `string | null` | default: `null` | - | - |
| `includeClosed` | `boolean` | default: `false` | - | - |
| `maxBeads` | `integer` | default: `40` | - | - |
| `rounds` | `integer` | default: `6` | - | - |
| `noMaterialChangeRoundsToStop` | `integer` | default: `2` | - | - |
| `maxBeadConcurrency` | `integer` | default: `6` | - | - |
| `reviewersPerBead` | `integer` | default: `3` | - | - |
| `strict` | `boolean` | default: `true` | - | - |
| `dryRun` | `boolean` | default: `false` | - | - |
| `planContext` | `string` | default: `"Use the selected beads as the source of truth. If a planPath is provided, selected beads should already embed the relevant source-plan decisions."` | - | - |

## Run

```bash
smithers workflow run beads-polish --input '{"selector":"plan","planPath":"docs/plans/fable/007-full-tool-socket-auth.md","beadIds":[],"label":null,"query":null,"includeClosed":false,"maxBeads":40,"rounds":6,"noMaterialChangeRoundsToStop":2,"maxBeadConcurrency":6,"reviewersPerBead":3,"strict":true,"dryRun":false,"planContext":"Use the selected beads as the source of truth. If a planPath is provided, selected beads should already embed the relevant source-plan decisions."}'
```

If the workflow defines a `prompt` field, `--prompt` is shorthand for `--input '{"prompt":"..."}'`.

```bash
smithers workflow inspect beads-polish --format json
```

## Operating Notes

- Workflow ID: `beads-polish`
- Entry file: `.smithers/workflows/beads-polish.tsx`
- Run from the repository root so `.smithers/agents.ts`, prompts, and relative imports resolve.
- Inspect progress with `smithers ps`, `smithers inspect <run-id>`, `smithers logs <run-id>`, and `smithers chat <run-id>`.
