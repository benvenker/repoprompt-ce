---
name: mission-kanban
description: Materialize an approved RepoPrompt CE source plan into covered Kanban tickets, execute them in mission worktree branches, and report source-plan satisfaction.
workflow: mission-kanban
---

# Mission Kanban

Use `mission-kanban` when an approved RepoPrompt CE plan should become a deterministic, bounded implementation campaign. It reads the source plan, generates and alignment-checks tickets, writes `.smithers/tickets/` files, executes tickets in isolated `mission/<ticket-slug>` worktree branches, integrates results, and writes a final source-plan satisfaction report.

## Inputs

- `planPath` (`string`, default `/data/projects/repoprompt-ce/docs/plans/2026-06-18-001-fix-headless-agent-run-lifecycle-parity-plan.md`): approved source plan to implement.
- `prompt` (`string`, optional): extra operator instructions or emphasis; use `--prompt` for simple runs.
- `maxTickets` (`int >= 7`, default `7`): maximum generated tickets, including the holistic integration/review ticket.
- `maxConcurrency` (`int >= 1`, default `3`): parallel ticket execution limit.
- `baseBranch` (`string`, optional): branch each ticket worktree starts from; omitted means current-branch fallback.
- `ticketBranchPrefix` (`string`, default `mission`): branch namespace for ticket worktrees.
- `overwriteTickets` (`boolean`, default `false`): whether to overwrite generated ticket files instead of refusing or safely archiving.

## Run

From the repository root:

```bash
bunx smithers-orchestrator workflow run mission-kanban --prompt "Implement the approved plan and report unresolved risks."
```

For structured inputs:

```bash
bunx smithers-orchestrator workflow run mission-kanban --input '{"planPath":"docs/plans/example.md","prompt":"Keep validation focused.","maxTickets":7,"maxConcurrency":3,"baseBranch":"main","ticketBranchPrefix":"mission","overwriteTickets":false}'
```

Run detached with `-d`, then watch it:

```bash
bunx smithers-orchestrator workflow run mission-kanban -d --input '{"planPath":"docs/plans/example.md","maxConcurrency":3}'
smithers ps
smithers logs <runId> -f
smithers inspect <runId>
```

## Blocked states

No approval or human-task nodes are expected in this workflow, but use the standard Smithers controls if a run blocks: `smithers approve <runId>` for approval gates, `smithers why <runId>` for signal waits, and `smithers cancel <runId>` to stop the run.
