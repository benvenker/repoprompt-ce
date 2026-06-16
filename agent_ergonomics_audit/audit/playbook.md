# Agent-Ergonomics Playbook: rpce-headless

Mode: audit-only.

## Highest Leverage Fixes

1. Add an in-tool capabilities / robot-docs contract.
   - This should be the canonical single source for a fresh agent: loaded root, tool exposure, root verification, context_builder defaults, agent_manage/agent_run pattern, oracle opt-in rule, fake-agent caveat, and smoke commands.

2. Fix CLI help ergonomics.
   - `rpce-headless --help`, bare `rpce-headless`, and every subcommand `--help` should be first-try friendly and exit 0.

3. Make read-only subagent onboarding the blessed path.
   - Recommended sequence: verify root, `agent_manage list_agents`, dispatch narrow read-only `agent_run` tasks, use `context_builder` for curated context, cleanup sessions, and integrate findings with direct evidence.

4. Simplify `context_builder` discovery.
   - The lifecycle is strong, but the current single schema carries sync mode, async mode, timeouts, response types, cleanup, and unsupported export behavior. Schema-only agents need either clearer examples in the schema or separate surfaces.

5. Teach `get_code_structure` fallback.
   - When codemaps are unavailable, the tool should tell agents to use `file_search` and targeted `read_file` rather than leaving them to infer the next move.

6. Surface loaded root in structured output.
   - The root negotiation fix works, but agents should not infer loaded root from ASCII tree labels.

## What Is Already Strong

- `serve`/`dump` default to current working directory when `--root` is omitted.
- Global Codex config guidance now says to run `args = ["serve"]`.
- Stdio vs discovery-restricted socket behavior is explicit and tested.
- `context_builder` has a real async lifecycle with start/poll/wait/get_result/cancel/cleanup.
- Fake-agent leakage is gated and tested.
- The generated Discover prompt is good once agents choose `context_builder`.
- Socket restrictions are safe by default, and authenticated full-tool socket mode exists for intentional full access.

## Product Interpretation

The headless surface is no longer just remote grep. The contract should encourage agents to use `context_builder` and read-only lower-powered subagents as the normal architecture-onboarding path. Oracle should remain explicit/on-demand because it is external inference rather than repo evidence.
