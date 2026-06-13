# RepoPrompt CE Agent Workflows

RepoPrompt CE uses local plans, Beads, and Smithers workflows to turn project intent into agent-executable work. This context names the planning and workflow concepts so future workflow changes use the same language.

## Language

**Plan**:
A written description of intended project work, usually scoped enough to become one or more Beads.
_Avoid_: spec, idea dump, ticket text

**Bead**:
An agent-executable unit of project work with enough context, validation criteria, and dependency information for a fresh agent to act on it.
_Avoid_: issue, task, ticket

**Bead Graph**:
A set of related Beads connected by dependency edges so implementation order and readiness are explicit.
_Avoid_: issue tree, dependency list

**Closure Parent**:
A Bead that represents completion of a larger plan and depends on the child Beads that actually carry the implementation work.
_Avoid_: epic, umbrella ticket

**Ready Frontier**:
The subset of open Beads that are currently safe for an agent to pick up because their prerequisites are satisfied.
_Avoid_: backlog top, next task

**Split Decision**:
An explicit note explaining why a plan became a single Bead or a Bead Graph.
_Avoid_: sizing note, decomposition comment

**Beads From Plan**:
The workflow activity that converts a Plan into plan-linked Beads or repairs the existing Beads for that plan.
_Avoid_: ticket generation, issue import

**Beads Polish**:
The workflow activity that improves existing Beads without implementing their product or code changes.
_Avoid_: cleanup, rewrite pass

**Quality Judge**:
An evaluator that compares Bead state against a rubric and emits structured quality evidence for the workflow.
_Avoid_: reviewer, approval bot

**Repair Prompt**:
The judge-produced instruction that tells the next workflow iteration what failed and how to improve it.
_Avoid_: feedback, notes

**Project-local Authority**:
The rule that repo-local Smithers skills, prompts, and workflow docs govern workflow behavior for this repository.
_Avoid_: global defaults, upstream guidance
