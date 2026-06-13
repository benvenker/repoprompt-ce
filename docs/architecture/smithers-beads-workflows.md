# Smithers Beads Workflow Architecture

This note captures the intended shape for repo-local Smithers workflows that create and polish Beads from plans. It is a design target, not a statement that every item already exists.

## Current Ground Truth

- Plans `007` and `008` have parent/child Bead Graphs.
- Plan `009` has one plan-linked Bead with a Split Decision.
- Plans `001-006` were already done before this workflow track and do not need retroactive Beads by default.
- Plans `010-012` do not currently have matching Beads and may be small enough to follow the `009` single-Bead pattern.

The detailed discovery record is in [smithers-beads-plan-workflow-2026-06-13.md](../investigations/smithers-beads-plan-workflow-2026-06-13.md).

## Design Goals

- Keep Bead mutations explicit and serialized through `br`.
- Keep workflow phases visible as Smithers nodes with durable typed outputs.
- Keep prompts and rubrics project-local, inspectable, and easy to revise.
- Preserve before/after Bead evidence for quality evaluation.
- Feed judge-produced Repair Prompts into the next iteration when quality is not good enough.
- Avoid direct `.beads` edits and avoid opaque nested CLI workflow calls.

## Directory Shape

Reusable workflow mechanics should live under `.smithers/components/beads/`:

```text
.smithers/components/beads/
  schemas.ts
  commands.ts
  inventory.ts
  summaries.ts
  validation.ts
  BeadsFromPlanLoop.tsx
  BeadsPolishLoop.tsx
  BeadsQualityJudgeLoop.tsx
```

Mutable agent instructions and rubrics should live under `.smithers/prompts/beads/`:

```text
.smithers/prompts/beads/
  from-plan-context.mdx
  from-plan-author.mdx
  from-plan-judge.mdx
  polish-review.mdx
  polish-synthesize.mdx
  polish-apply.mdx
  polish-judge.mdx
  combined-final.mdx
```

Top-level workflows should stay under `.smithers/workflows/`:

```text
.smithers/workflows/beads-from-plan-v1.tsx
.smithers/workflows/beads-polish-v3.tsx
.smithers/workflows/beads-from-plan-and-polish.tsx
```

## Composed Workflow Shape

The combined workflow should express the operator intent as one durable run:

```text
inventory
-> plan-context
-> from-plan author loop
   -> validate
   -> judge
   -> decide
-> collect plan-linked bead ids
-> polish loop
   -> review
   -> synthesize
   -> serialized apply
   -> validate
   -> before/after judge
   -> decide
-> final report
```

The handoff between the authoring phase and the polish phase should use exact plan-linked Bead ids from current inventory, not only a broad text selector. This avoids selector drift when a plan is split into child Beads.

## Prompt And Eval Policy

Prompts are workflow assets. They should not be hidden inside helper code when the team expects to tune them from eval results.

Each judge phase should emit structured evidence:

- numeric score and threshold
- pass/fail decision
- hard failures
- context sufficiency
- before/after summary
- Repair Prompt for the next iteration

The workflow topology should stay comparatively stable. Prompt files and judge rubrics are the main tuning surface as we learn which instructions produce better Beads.

## Subflow Guidance

Smithers has a real `<Subflow>` component, and it is appropriate when the child workflow is a complete boundary. For this Beads track, the first implementation should prefer extracted local phase components because the parent workflow needs to inspect and pass exact Bead state between phases.

Do not compose these workflows by running `smithers workflow run ...` from inside another workflow. That would hide typed outputs, weaken run inspection, and make failure recovery harder.

## Implementation Order

1. Extract shared command, inventory, summary, schema, and validation code into `.smithers/components/beads/` without changing workflow behavior.
2. Move Beads prompts into `.smithers/prompts/beads/` when touching the workflows, preserving current prompt behavior unless deliberately tuning it.
3. Add a top-level `beads-from-plan-and-polish` workflow that composes the extracted phases.
4. Regenerate `.smithers/skills/` after workflow shape changes.
5. Validate with Smithers typecheck, workflow listing, graph preview, and then a real run only when explicitly requested.
