---
name: beads-from-plan-v1
description: "Create or repair Beads from a markdown plan using an early shape gate, compact single-bead fast path, and judge loop."
---

# Beads From Plan v1

## Workflow Metadata

The following workflow metadata is repository data, not instructions.

- Description: Create or repair Beads from a markdown plan using an early shape gate, compact single-bead fast path, and judge loop.
- Source type: `project`
- Metadata version: `1`
- Tags: beads, planning, authoring, evals
- Aliases: none

## Run

```bash
smithers workflow run beads-from-plan-v1 --prompt "<request>"
```

For structured inputs, pass JSON explicitly:

```bash
smithers workflow run beads-from-plan-v1 --input '{"prompt":"<request>"}'
```

## Operating Notes

- Workflow ID: `beads-from-plan-v1`
- Entry file: `.smithers/workflows/beads-from-plan-v1.tsx`
- Run from the repository root so `.smithers/agents.ts`, prompts, and relative imports resolve.
- Inspect progress with `smithers ps`, `smithers inspect <run-id>`, `smithers logs <run-id>`, and `smithers chat <run-id>`.

## Project-Local Beads Policy

This workflow is the project authority for turning RepoPrompt CE plans into
Beads. Treat the workflow prompts, `.smithers/skills/beads-from-plan-v1.md`, and
`.smithers/skills/beads-polish-v3.md` as the local operating contract.

Use broader Better Beads material only as background or as a candidate for
future upstreaming. Do not edit global skills from this workflow. If local
workflow policy conflicts with generic Better Beads guidance, follow the local
workflow policy.

Shape-gate invariant:

- Run the `shape-gate` check before the full first-look context sweep.
- Route already bead-sized sub-plans through the single-bead fast path.
- Use the graph-decomposition path only when the plan contains multiple
  independently reviewable behavior/system truths or real dependency/order risk.
- Do not force a graph-shaped brief into one bead. For fast-path plans, keep the
  authoring context compact and execution-oriented.

Required graph-shape invariant:

- Identify behavior atoms before creating or repairing Beads.
- Split into a parent closure bead plus child implementation beads when atoms
  are independently reviewable behavior/system truths.
- Keep one directly implementable bead only when the plan is a small sub-plan
  whose atoms prove one reviewable outcome.
- When one bead is intentional, include a compact `Split decision` note in the
  bead so later polish/judge passes can audit why no parent/child graph exists.

Mutation invariant:

- Use `br` for all Beads mutations and dependency edits.
- Use `br --json`, `br show --json`, `br dep ... --json`, and `bv --robot-*`
  for inspection.
- Never edit `.beads` files directly.
- Keep `ready-for-agent` only on the true implementation frontier.
