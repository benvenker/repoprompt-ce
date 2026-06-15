---
name: work-from-plan
description: "Execute the latest or specified repository plan document through a Smithers manifest, validation, and review workflow."
---

# Work From Plan

## Run

```bash
smithers workflow run work-from-plan --input '{"planPath":null,"prompt":"","commit":false}'
```

To execute a specific plan:

```bash
smithers workflow run work-from-plan --input '{"planPath":"docs/plans/example.md","prompt":"","commit":false}'
```

## Operating Notes

- Workflow ID: `work-from-plan`
- Entry file: `.smithers/workflows/work-from-plan.tsx`
- Blank `planPath` selects the newest `docs/plans/*.md` or `docs/plans/*.html` by modification time.
- The workflow treats plans as immutable decision artifacts; progress lives in Smithers run state, validation evidence, and optional commits.
- Execution is serial by default. Parallel isolated-worktree execution is intentionally left for a later workflow revision.
- Commit mode defaults to `false`. If enabled, workers must stage only intended files and run repo-local preflight before committing.
