// smithers-source: project
// smithers-metadata-version: 1
// smithers-display-name: Beads From Plan v1
// smithers-description: Create or repair Beads from a markdown plan using an Opus first-look brief and a GPT-5.5 high judge loop.
// smithers-tags: beads,planning,authoring,evals
/** @jsxImportSource smithers-orchestrator */
import { createSmithers } from "smithers-orchestrator";
import { createScorer } from "smithers-orchestrator/scorers";
import { z } from "zod/v4";
import { Codex55HighAgent } from "../agents/codex";
import { ClaudeCodeOpusAgent } from "../agents/claude-code";
import ContextPrompt from "../prompts/beads-from-plan-v1-context.mdx";
import AuthorPrompt from "../prompts/beads-from-plan-v1-author.mdx";
import JudgePrompt from "../prompts/beads-from-plan-v1-judge.mdx";
import FinalPrompt from "../prompts/beads-from-plan-v1-final.mdx";

const beadSchema = z.looseObject({
  id: z.string(),
  title: z.string().default(""),
  description: z.string().default(""),
  status: z.string().default(""),
  priority: z.number().optional(),
  issue_type: z.string().optional(),
  labels: z.array(z.string()).default([]),
  external_ref: z.string().nullable().optional(),
  dependencies: z.array(z.looseObject({
    id: z.string(),
    title: z.string().default(""),
    status: z.string().default(""),
    priority: z.number().optional(),
    dependency_type: z.string().optional(),
  })).default([]),
  dependents: z.array(z.looseObject({
    id: z.string(),
    title: z.string().default(""),
    status: z.string().default(""),
    priority: z.number().optional(),
    dependency_type: z.string().optional(),
  })).default([]),
});

const commandResultSchema = z.looseObject({
  command: z.string(),
  exitCode: z.number().int(),
  stdout: z.string().default(""),
  stderr: z.string().default(""),
});

const inventorySchema = z.looseObject({
  selectorSummary: z.string(),
  selectedCount: z.number().int(),
  selectedBeads: z.array(beadSchema).default([]),
  warnings: z.array(z.string()).default([]),
  graphSummary: z.string().default(""),
});

const contextBriefSchema = z.looseObject({
  planPath: z.string(),
  laneLabel: z.string(),
  planSummary: z.string().default(""),
  finalDecisions: z.array(z.string()).default([]),
  proposedGraphShape: z.string().default(""),
  contextSweep: z.array(z.string()).default([]),
  anchors: z.array(z.string()).default([]),
  validationPlan: z.array(z.string()).default([]),
  risks: z.array(z.string()).default([]),
  authoringInstructions: z.string().default(""),
});

const authoringSchema = z.looseObject({
  mode: z.enum(["create", "repair"]).default("create"),
  createdIds: z.array(z.string()).default([]),
  updatedIds: z.array(z.string()).default([]),
  dependencyEdges: z.array(z.string()).default([]),
  commandsRun: z.array(z.string()).default([]),
  summary: z.string().default(""),
  remainingConcerns: z.array(z.string()).default([]),
});

const validationSchema = z.looseObject({
  passed: z.boolean().default(false),
  selectedCount: z.number().int().default(0),
  selectedBeads: z.array(beadSchema).default([]),
  cyclesCount: z.number().int().default(0),
  qualityGatePassed: z.boolean().default(false),
  graphPlanAvailable: z.boolean().default(false),
  commandResults: z.array(commandResultSchema).default([]),
  warnings: z.array(z.string()).default([]),
  summary: z.string().default(""),
});

const judgeSchema = z.looseObject({
  passed: z.boolean().default(false),
  overallScore: z.number().min(0).max(1).default(0),
  overallScore30: z.number().min(0).max(30).default(0),
  threshold: z.number().min(0).max(1).default(0.86),
  verdict: z.enum(["ready", "repair", "blocked", "empty"]).default("repair"),
  hardFailures: z.array(z.string()).default([]),
  warnings: z.array(z.string()).default([]),
  beadResults: z.array(z.looseObject({
    beadId: z.string(),
    score30: z.number().min(0).max(30).default(0),
    passed: z.boolean().default(false),
    hardFailures: z.array(z.string()).default([]),
    warnings: z.array(z.string()).default([]),
    repairInstructions: z.array(z.string()).default([]),
  })).default([]),
  contextSweepRequests: z.array(z.looseObject({
    purpose: z.string(),
    suggestedCommands: z.array(z.string()).default([]),
    expectedEvidence: z.string().default(""),
  })).default([]),
  repairPrompt: z.string().default(""),
  summary: z.string().default(""),
  markdownBody: z.string().default(""),
});

const decisionSchema = z.looseObject({
  passed: z.boolean().default(false),
  shouldContinue: z.boolean().default(true),
  scoreText: z.string().default("0.00"),
  thresholdText: z.string().default("0.86"),
  scorePercent: z.number().int().min(0).max(100).default(0),
  thresholdPercent: z.number().int().min(0).max(100).default(86),
  hardFailures: z.array(z.string()).default([]),
  feedback: z.string().default(""),
  summary: z.string().default(""),
});

const finalSchema = z.looseObject({
  status: z.enum(["ready", "partial", "blocked", "empty"]).default("partial"),
  summary: z.string().default(""),
  createdIds: z.array(z.string()).default([]),
  updatedIds: z.array(z.string()).default([]),
  selectedCount: z.number().int().default(0),
  roundsRun: z.number().int().default(0),
  judgeScoreText: z.string().default("0.00"),
  judgeThresholdText: z.string().default("0.86"),
  judgeScorePercent: z.number().int().min(0).max(100).default(0),
  judgeThresholdPercent: z.number().int().min(0).max(100).default(86),
  remainingRisks: z.array(z.string()).default([]),
  nextActions: z.array(z.string()).default([]),
  markdownBody: z.string().default(""),
});

const inputSchema = z.object({
  planPath: z.string().default("docs/plans/fable/008-agent-process-lifecycle.md"),
  laneLabel: z.string().default("fable-008"),
  userContext: z.string().default("Create Beads from this plan so beads-polish-v3 can polish them next."),
  rounds: z.number().int().min(1).max(8).default(4),
  strict: z.boolean().default(true),
  judgeThresholdPercent: z.number().int().min(0).max(100).default(86),
});

const { Workflow, Task, Sequence, Loop, smithers, outputs } = createSmithers({
  input: inputSchema,
  inventory: inventorySchema,
  contextBrief: contextBriefSchema,
  authoring: authoringSchema,
  validation: validationSchema,
  judge: judgeSchema,
  decision: decisionSchema,
  final: finalSchema,
});

type CommandResult = z.infer<typeof commandResultSchema>;

const opusFirstLookAgents = [ClaudeCodeOpusAgent, Codex55HighAgent];
const gpt55HighAgents = [Codex55HighAgent];

const beadCreationScorer = createScorer({
  id: "beads-from-plan-quality-score",
  name: "Beads From Plan Quality Score",
  description: "Stores the LLM judge score for a newly authored plan-linked Beads graph.",
  score: async ({ output }) => {
    const result = output as any;
    const score = Math.max(0, Math.min(1, Number(result?.overallScore ?? 0)));
    return {
      score,
      reason: String(result?.summary ?? result?.verdict ?? ""),
      meta: {
        verdict: result?.verdict,
        passed: result?.passed,
        threshold: result?.threshold,
        hardFailures: Array.isArray(result?.hardFailures) ? result.hardFailures : [],
      },
    };
  },
});

function asArray(value: unknown): any[] {
  if (Array.isArray(value)) return value;
  if (value && typeof value === "object" && Array.isArray((value as any).issues)) return (value as any).issues;
  return [];
}

function lower(value: unknown): string {
  return String(value ?? "").toLowerCase();
}

function quoteCommand(argv: string[]) {
  return argv.map((part) => part.includes(" ") ? JSON.stringify(part) : part).join(" ");
}

async function runCommand(argv: string[], timeoutMs = 120_000): Promise<CommandResult> {
  const proc = Bun.spawn(argv, {
    stdout: "pipe",
    stderr: "pipe",
  });
  const timeout = setTimeout(() => proc.kill(), timeoutMs);
  const [stdout, stderr, exitCode] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
    proc.exited,
  ]);
  clearTimeout(timeout);
  return {
    command: quoteCommand(argv),
    exitCode,
    stdout,
    stderr,
  };
}

async function readJsonCommand(argv: string[]): Promise<any> {
  const result = await runCommand(argv);
  if (result.exitCode !== 0) {
    throw new Error(`${result.command} failed with ${result.exitCode}: ${result.stderr || result.stdout}`);
  }
  return JSON.parse(result.stdout || "null");
}

async function showBead(id: string): Promise<any | null> {
  const result = await runCommand(["br", "show", id, "--json"]);
  if (result.exitCode !== 0) return null;
  try {
    return asArray(JSON.parse(result.stdout))[0] ?? null;
  } catch {
    return null;
  }
}

function compactLinkedBead(bead: any) {
  return {
    id: String(bead.id ?? ""),
    title: String(bead.title ?? ""),
    status: String(bead.status ?? ""),
    priority: bead.priority,
    dependency_type: bead.dependency_type,
  };
}

function compactBead(bead: any) {
  return {
    id: String(bead.id ?? ""),
    title: String(bead.title ?? ""),
    description: String(bead.description ?? ""),
    status: String(bead.status ?? ""),
    priority: bead.priority,
    issue_type: bead.issue_type,
    labels: Array.isArray(bead.labels) ? bead.labels : [],
    external_ref: bead.external_ref ?? null,
    dependencies: (Array.isArray(bead.dependencies) ? bead.dependencies : []).map(compactLinkedBead),
    dependents: (Array.isArray(bead.dependents) ? bead.dependents : []).map(compactLinkedBead),
  };
}

function matchesPlanOrLabel(bead: any, planPath: string, laneLabel: string) {
  const labels = Array.isArray(bead.labels) ? bead.labels.map(String) : [];
  const externalRef = lower(bead.external_ref);
  const plan = lower(planPath);
  return externalRef.includes(plan) || labels.includes(laneLabel);
}

function buildGraphSummary(selectedBeads: any[], planPath: string, laneLabel: string) {
  const selectedIds = new Set(selectedBeads.map((bead) => String(bead.id)));
  const lines = [
    `Selector: planPath=${planPath}; laneLabel=${laneLabel}`,
    `Selected beads: ${selectedBeads.length}`,
    "",
    "## Selected Beads",
    ...selectedBeads.map((bead: any) => {
      const labels = Array.isArray(bead.labels) && bead.labels.length > 0 ? ` labels=${bead.labels.join(",")}` : "";
      return `- ${bead.id}: ${bead.title} [${bead.status}]${labels}`;
    }),
    "",
    "## Local Edges",
  ];

  for (const bead of selectedBeads) {
    const deps = (bead.dependencies ?? [])
      .map((dep: any) => String(dep.id))
      .filter((id: string) => selectedIds.has(id));
    const dependents = (bead.dependents ?? [])
      .map((dep: any) => String(dep.id))
      .filter((id: string) => selectedIds.has(id));
    lines.push(`- ${bead.id}`);
    lines.push(`  deps: ${deps.length > 0 ? deps.join(", ") : "(none in selection)"}`);
    lines.push(`  dependents: ${dependents.length > 0 ? dependents.join(", ") : "(none in selection)"}`);
  }

  return lines.join("\n");
}

async function buildInventory(input: z.infer<typeof inputSchema>) {
  const list = await readJsonCommand(["br", "list", "--all", "--limit", "0", "--json"]);
  const issues = asArray(list);
  const selectedBase = issues.filter((bead) => matchesPlanOrLabel(bead, input.planPath, input.laneLabel));

  const selectedBeads = [];
  for (const bead of selectedBase) {
    selectedBeads.push(compactBead((await showBead(String(bead.id))) ?? bead));
  }

  const warnings = [];
  if (selectedBeads.length === 0) warnings.push("No beads are linked to this planPath or laneLabel yet.");

  return {
    selectorSummary: `planPath=${input.planPath}; laneLabel=${input.laneLabel}`,
    selectedCount: selectedBeads.length,
    selectedBeads,
    warnings,
    graphSummary: buildGraphSummary(selectedBeads, input.planPath, input.laneLabel),
  };
}

async function validateGraph(input: z.infer<typeof inputSchema>) {
  const inventory = await buildInventory(input);
  const beadIds = inventory.selectedBeads.map((bead: any) => String(bead.id));
  const commandResults: CommandResult[] = [];

  commandResults.push(await runCommand(["br", "dep", "cycles", "--json"]));
  commandResults.push(await runCommand(["bv", "--robot-insights"]));
  commandResults.push(await runCommand(["bv", "--robot-plan"]));

  const repoGate = ".agents/skills/better-beads/scripts/bead_quality_gate.py";
  const homeGate = process.env.HOME
    ? `${process.env.HOME}/.agents/skills/better-beads/scripts/bead_quality_gate.py`
    : undefined;
  let gate: string | null = null;
  for (const candidate of [repoGate, process.env.BETTER_BEADS_QUALITY_GATE, homeGate]) {
    if (candidate && await Bun.file(candidate).exists()) {
      gate = candidate;
      break;
    }
  }

  if (gate && beadIds.length > 0) {
    for (const id of beadIds) {
      const argv = ["python3", gate, "--id", id];
      if (input.strict) argv.push("--strict");
      commandResults.push(await runCommand(argv, 180_000));
    }
  } else if (!gate) {
    commandResults.push({
      command: "bead_quality_gate.py",
      exitCode: 127,
      stdout: "",
      stderr: "Could not find repo-local or global better-beads quality gate.",
    });
  }

  let cyclesCount = 0;
  try {
    const cycles = JSON.parse(commandResults[0]?.stdout || "{}");
    cyclesCount = Number(cycles.count ?? cycles.cycles?.length ?? 0);
  } catch {
    cyclesCount = -1;
  }

  const gateResults = commandResults.slice(3);
  const qualityGatePassed = beadIds.length > 0 && gateResults.length > 0 && gateResults.every((result) => {
    if (result.exitCode === 0) return true;
    if (result.stdout.includes("0 error(s)") && result.stdout.includes("[WARNING]")) return true;
    return false;
  });
  const graphPlanAvailable = (commandResults[2]?.exitCode ?? 1) === 0;
  const passed = inventory.selectedCount > 0 && cyclesCount === 0 && qualityGatePassed && graphPlanAvailable;
  const warnings = [...inventory.warnings];
  if (cyclesCount !== 0) warnings.push(`Dependency cycle count is ${cyclesCount}.`);
  if (!qualityGatePassed) warnings.push("One or more Beads quality gates had blocking errors.");
  if (!graphPlanAvailable) warnings.push("bv --robot-plan did not produce a usable plan.");

  return {
    passed,
    selectedCount: inventory.selectedCount,
    selectedBeads: inventory.selectedBeads,
    cyclesCount,
    qualityGatePassed,
    graphPlanAvailable,
    commandResults,
    warnings,
    summary: passed
      ? `Created graph passed deterministic validation with ${inventory.selectedCount} plan-linked bead(s); warning-only gate output is advisory.`
      : `Created graph needs repair; ${inventory.selectedCount} plan-linked bead(s) found.`,
  };
}

function judgeThreshold(input: z.infer<typeof inputSchema>): number {
  return Math.max(0, Math.min(1, Number(input.judgeThresholdPercent ?? 86) / 100));
}

function decide(judge: any, input: z.infer<typeof inputSchema>) {
  const threshold = judgeThreshold(input);
  const score = Math.max(0, Math.min(1, Number(judge?.overallScore ?? 0)));
  const hardFailures = Array.isArray(judge?.hardFailures) ? judge.hardFailures : [];
  const passed = Boolean(judge?.passed) && score >= threshold && hardFailures.length === 0;
  return {
    passed,
    shouldContinue: !passed,
    scoreText: score.toFixed(2),
    thresholdText: threshold.toFixed(2),
    scorePercent: Math.round(score * 100),
    thresholdPercent: Math.round(threshold * 100),
    hardFailures,
    feedback: String(judge?.repairPrompt ?? judge?.summary ?? ""),
    summary: passed
      ? `Judge passed plan-linked Beads at ${score.toFixed(2)} / ${threshold.toFixed(2)}.`
      : `Judge requested another authoring pass at ${score.toFixed(2)} / ${threshold.toFixed(2)}.`,
  };
}

export default smithers((ctx) => {
  const initialInventory = ctx.outputMaybe("inventory", { nodeId: "initial-inventory", iteration: 0 });
  const contextBrief = ctx.outputMaybe("contextBrief", { nodeId: "opus-first-look", iteration: 0 });
  const validations = ctx.outputs.validation ?? [];
  const authoringResults = ctx.outputs.authoring ?? [];
  const judges = ctx.outputs.judge ?? [];
  const decisions = ctx.outputs.decision ?? [];
  const lastValidation = validations.at(-1);
  const lastJudge = judges.at(-1);
  const lastDecision = decisions.at(-1);
  const currentInventory = lastValidation
    ? {
      selectedCount: lastValidation.selectedCount,
      selectedBeads: lastValidation.selectedBeads,
      warnings: lastValidation.warnings,
    }
    : initialInventory;
  const previousFeedback = lastDecision
    ? {
      decision: lastDecision,
      judge: lastJudge,
      validation: lastValidation,
    }
    : {};
  const done = Boolean(lastDecision?.passed === true);
  const maxRoundsReached = decisions.length >= (ctx.input.rounds ?? 4);

  return (
    <Workflow name="beads-from-plan-v1">
      <Sequence>
        <Task id="initial-inventory" output={outputs.inventory}>
          {async () => buildInventory(ctx.input)}
        </Task>

        <Task
          id="opus-first-look"
          output={outputs.contextBrief}
          agent={opusFirstLookAgents}
          timeoutMs={1_200_000}
          heartbeatTimeoutMs={240_000}
          retries={1}
        >
          <ContextPrompt
            planPath={ctx.input.planPath}
            laneLabel={ctx.input.laneLabel}
            userContext={ctx.input.userContext}
          />
        </Task>

        {contextBrief ? (
          <Loop id="author:judge-loop" until={done} maxIterations={ctx.input.rounds ?? 4} onMaxReached="return-last">
            <Sequence>
              <Task
                id="author-br"
                output={outputs.authoring}
                agent={gpt55HighAgents}
                continueOnFail
                timeoutMs={1_200_000}
                heartbeatTimeoutMs={240_000}
              >
                <AuthorPrompt
                  planPath={ctx.input.planPath}
                  laneLabel={ctx.input.laneLabel}
                  strict={ctx.input.strict ? "true" : "false"}
                  contextBrief={JSON.stringify(contextBrief, null, 2)}
                  currentInventory={JSON.stringify(currentInventory ?? {}, null, 2)}
                  previousFeedback={JSON.stringify(previousFeedback, null, 2)}
                />
              </Task>

              <Task id="validate-created-graph" output={outputs.validation}>
                {async () => validateGraph(ctx.input)}
              </Task>

              <Task
                id="judge-created-graph"
                output={outputs.judge}
                agent={gpt55HighAgents}
                needs={{ author: "author-br", validation: "validate-created-graph" }}
                deps={{ author: outputs.authoring, validation: outputs.validation }}
                timeoutMs={900_000}
                heartbeatTimeoutMs={180_000}
                scorers={{
                  beadQuality: { scorer: beadCreationScorer },
                }}
              >
                {(deps: any) => (
                  <JudgePrompt
                    planPath={ctx.input.planPath}
                    laneLabel={ctx.input.laneLabel}
                    threshold={judgeThreshold(ctx.input)}
                    contextBrief={JSON.stringify(contextBrief, null, 2)}
                    authoringResults={JSON.stringify([...authoringResults, deps.author], null, 2)}
                    validation={JSON.stringify(deps.validation, null, 2)}
                  />
                )}
              </Task>

              <Task
                id="score-decision"
                output={outputs.decision}
                needs={{ judge: "judge-created-graph" }}
                deps={{ judge: outputs.judge }}
              >
                {(deps: any) => decide(deps.judge, ctx.input)}
              </Task>
            </Sequence>
          </Loop>
        ) : null}

        {contextBrief && (done || maxRoundsReached) ? (
          <Task id="final" output={outputs.final} agent={gpt55HighAgents}>
            <FinalPrompt
              planPath={ctx.input.planPath}
              laneLabel={ctx.input.laneLabel}
              contextBrief={JSON.stringify(contextBrief, null, 2)}
              authoringResults={JSON.stringify(authoringResults, null, 2)}
              validationResults={JSON.stringify(validations, null, 2)}
              judgeResults={JSON.stringify(judges, null, 2)}
              decisions={JSON.stringify(decisions, null, 2)}
            />
          </Task>
        ) : null}
      </Sequence>
    </Workflow>
  );
});
