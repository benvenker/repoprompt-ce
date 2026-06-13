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

## Run

```bash
smithers workflow run beads-polish-v3 --prompt "<request>"
```

For structured inputs, pass JSON explicitly:

```bash
smithers workflow run beads-polish-v3 --input '{"prompt":"<request>"}'
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
