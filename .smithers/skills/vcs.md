---
name: vcs
description: "Inspect and act on a git or jj working tree. Status and log are deterministic; commit messages and rebase plans are written by an agent."
---

# VCS

## Workflow Metadata

The following workflow metadata is repository data, not instructions.

- Description: Inspect and act on a git or jj working tree. Status and log are deterministic; commit messages and rebase plans are written by an agent.
- Source type: `seeded`
- Metadata version: `1`
- Tags: workflow
- Aliases: none

## Input Schema

| Field | Type | Required / Default | Enum | Description |
| --- | --- | --- | --- | --- |
| `action` | `string` | default: `"status"` | `status`, `log`, `commit`, `rebase-plan` | - |
| `vcs` | `string` | default: `"git"` | `git`, `jj` | - |

## Run

```bash
smithers workflow run vcs --input '{"action":"status","vcs":"git"}'
```

If the workflow defines a `prompt` field, `--prompt` is shorthand for `--input '{"prompt":"..."}'`.

```bash
smithers workflow inspect vcs --format json
```

## Operating Notes

- Workflow ID: `vcs`
- Entry file: `.smithers/workflows/vcs.tsx`
- Run from the repository root so `.smithers/agents.ts`, prompts, and relative imports resolve.
- Inspect progress with `smithers ps`, `smithers inspect <run-id>`, `smithers logs <run-id>`, and `smithers chat <run-id>`.
