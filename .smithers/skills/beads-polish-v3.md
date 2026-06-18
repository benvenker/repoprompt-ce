---
name: beads-polish-v3
description: "Polish selected Beads in a score-driven verifier loop with before/after evidence and judge telemetry."
---

# Beads Polish v3

## Workflow Metadata

The following workflow metadata is repository data, not instructions.

- Description: Polish selected Beads in a score-driven verifier loop with before/after evidence and judge telemetry.
- Source type: `project`
- Metadata version: `1`
- Tags: beads, planning, review, polish, evals
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
| `judgeThresholdPercent` | `integer` | default: `80` | - | - |
| `planContext` | `string` | default: `"Use the selected beads as the source of truth. If a planPath is provided, selected beads should already embed the relevant source-plan decisions."` | - | - |

## Run

```bash
smithers workflow run beads-polish-v3 --input '{"selector":"plan","planPath":"docs/plans/fable/007-full-tool-socket-auth.md","beadIds":[],"label":null,"query":null,"includeClosed":false,"maxBeads":40,"rounds":6,"noMaterialChangeRoundsToStop":2,"maxBeadConcurrency":6,"reviewersPerBead":3,"strict":true,"dryRun":false,"judgeThresholdPercent":80,"planContext":"Use the selected beads as the source of truth. If a planPath is provided, selected beads should already embed the relevant source-plan decisions."}'
```

If the workflow defines a `prompt` field, `--prompt` is shorthand for `--input '{"prompt":"..."}'`.

```bash
smithers workflow inspect beads-polish-v3 --format json
```

## Operating Notes

- Workflow ID: `beads-polish-v3`
- Entry file: `.smithers/workflows/beads-polish-v3.tsx`
- Run from the repository root so `.smithers/agents.ts`, prompts, and relative imports resolve.
- Inspect progress with `smithers ps`, `smithers inspect <run-id>`, `smithers logs <run-id>`, and `smithers chat <run-id>`.

## Project-Local Beads Policy

This workflow is the project authority for polishing RepoPrompt CE Beads. Treat
the workflow prompts, `.smithers/skills/beads-polish-v3.md`, and
`.smithers/skills/beads-from-plan-v1.md` as the local operating contract.

Use broader Better Beads material only as background or as a candidate for
future upstreaming. Do not edit global skills from this workflow. If local
workflow policy conflicts with generic Better Beads guidance, follow the local
workflow policy.

Polish-loop invariant:

- Improve graph truth, execution readiness, verification clarity, and BV
  readability; do not endlessly reword a bead that is already strict-clean.
- Classify findings as same-contract detail, new independent behavior, graph
  correction, readability-only, or no-op before mutating.
- Run a split decision for dense or plan-derived single beads.
- A single dense bead must either carry a convincing `Split decision` note or be
  repaired into a parent/child graph.
- The judge should produce repair instructions that tell the next iteration what
  failed, what context must be swept, and which `br` mutation style should fix
  it.

Mutation invariant:

- Use `br` for all Beads mutations and dependency edits.
- Use `br --json`, `br show --json`, `br dep ... --json`, and `bv --robot-*`
  for inspection.
- Never edit `.beads` files directly.
- Keep `ready-for-agent` only on the true implementation frontier.
