# Compose Beads workflows with local components and prompts

RepoPrompt CE will compose the Beads-from-plan and Beads-polish workflow family through repo-local Smithers components and prompt assets, rather than by shelling from one Smithers workflow into another. The reusable workflow mechanics belong under `.smithers/components/beads/`, while mutable agent behavior and rubrics belong under `.smithers/prompts/beads/`, so each phase remains inspectable, evaluable, and tunable without copy-pasting whole workflows.

## Considered Options

- Shell one workflow into another with the Smithers CLI.
- Use Smithers `<Subflow>` for complete child workflow boundaries.
- Extract shared phase components and build a top-level composed workflow from those phases.

## Consequences

The composed workflow should preserve durable node outputs for inventory, authoring, validation, judge results, repair prompts, and final summaries. Existing standalone workflows can remain useful entry points, but future shared behavior should move into `.smithers/components/beads/` before creating or expanding a top-level plan-to-polish workflow.
