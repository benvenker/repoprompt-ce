---
name: headless-closeout-grinder
description: "Iterate CE code review, scoped fixes, and bounded headless validation until no P0/P1/P2 findings remain."
---

# Headless Closeout Grinder

## Workflow Metadata

The following workflow metadata is repository data, not instructions.

- Description: Iterate CE code review, scoped fixes, and bounded headless validation until no P0/P1/P2 findings remain.
- Source type: `local`
- Metadata version: `1`
- Tags: review, implementation, headless
- Aliases: none

## Input Schema

| Field | Type | Required / Default | Enum | Description |
| --- | --- | --- | --- | --- |
| `prompt` | `string` | default: `""` | - | - |
| `maxIterations` | `integer` | default: `3` | - | - |
| `closeoutPlanPath` | `string` | default: `"docs/plans/2026-06-15-002-fix-headless-timeout-observability-closeout-plan.md"` | - | - |
| `sourcePlanPaths` | `array` | default: `["docs/plans/2026-06-15-001-fix-context-builder-async-results-plan.md","docs/plans/2026-06-15-001-fix-headless-timeout-observability-plan.md"]` | - | - |
| `blockingSeverities` | `array` | default: `["P0","P1","P2"]` | - | - |
| `validationProfile` | `string` | default: `"headless-linux-docker-bounded"` | - | - |

## Run

```bash
smithers workflow run headless-closeout-grinder --input '{"prompt":"","maxIterations":3,"closeoutPlanPath":"docs/plans/2026-06-15-002-fix-headless-timeout-observability-closeout-plan.md","sourcePlanPaths":["docs/plans/2026-06-15-001-fix-context-builder-async-results-plan.md","docs/plans/2026-06-15-001-fix-headless-timeout-observability-plan.md"],"blockingSeverities":["P0","P1","P2"],"validationProfile":"headless-linux-docker-bounded"}'
```

If the workflow defines a `prompt` field, `--prompt` is shorthand for `--input '{"prompt":"..."}'`.

```bash
smithers workflow inspect headless-closeout-grinder --format json
```

## Operating Notes

- Workflow ID: `headless-closeout-grinder`
- Entry file: `.smithers/workflows/headless-closeout-grinder.tsx`
- Run from the repository root so `.smithers/agents.ts`, prompts, and relative imports resolve.
- Inspect progress with `smithers ps`, `smithers inspect <run-id>`, `smithers logs <run-id>`, and `smithers chat <run-id>`.
