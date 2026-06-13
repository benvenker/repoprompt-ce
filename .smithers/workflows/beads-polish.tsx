// smithers-source: project
// smithers-metadata-version: 1
// smithers-display-name: Beads Polish
// smithers-description: Iteratively polish a selected Beads graph with parallel review, serialized br mutations, and strict validation.
// smithers-tags: beads, planning, review, polish
/** @jsxImportSource smithers-orchestrator */
import { createSmithers } from "smithers-orchestrator";
import { z } from "zod/v4";
import { agents } from "../agents";
import ReviewPrompt from "../prompts/beads-polish-review.mdx";
import SynthesizePrompt from "../prompts/beads-polish-synthesize.mdx";
import ApplyPrompt from "../prompts/beads-polish-apply.mdx";
import FinalPrompt from "../prompts/beads-polish-final.mdx";

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

const reviewSchema = z.looseObject({
  beadId: z.string(),
  reviewer: z.string(),
  focus: z.string(),
  verdict: z.enum(["ready", "needs-polish", "split", "merge", "blocked", "defer"]).default("needs-polish"),
  score: z.number().min(0).max(30).default(24),
  hardFailures: z.array(z.string()).default([]),
  warnings: z.array(z.string()).default([]),
  findings: z.array(z.object({
    category: z.enum(["same-contract-detail", "new-independent-behavior", "graph-correction", "readability-only", "no-op"]),
    severity: z.enum(["critical", "major", "minor", "nit"]).default("minor"),
    summary: z.string(),
    recommendation: z.string(),
  })).default([]),
  readyForAgent: z.boolean().default(false),
});

const synthesisSchema = z.looseObject({
  beadId: z.string(),
  title: z.string().default(""),
  verdict: z.enum(["ready", "needs-polish", "split", "merge", "blocked", "defer"]).default("needs-polish"),
  score: z.number().min(0).max(30).default(24),
  materialChangeRecommended: z.boolean().default(false),
  rationale: z.string().default(""),
  sameContractDetails: z.array(z.string()).default([]),
  independentBehaviors: z.array(z.string()).default([]),
  graphCorrections: z.array(z.string()).default([]),
  readabilityChanges: z.array(z.string()).default([]),
  brMutationPlan: z.array(z.string()).default([]),
  readyForAgent: z.boolean().default(false),
});

const applySchema = z.looseObject({
  applied: z.boolean().default(false),
  dryRun: z.boolean().default(false),
  materialChanges: z.boolean().default(false),
  changedBeadIds: z.array(z.string()).default([]),
  commandsRun: z.array(z.string()).default([]),
  skippedRecommendations: z.array(z.string()).default([]),
  summary: z.string().default(""),
});

const validationSchema = z.looseObject({
  passed: z.boolean().default(false),
  cyclesCount: z.number().int().default(0),
  qualityGatePassed: z.boolean().default(false),
  graphPlanAvailable: z.boolean().default(false),
  commandResults: z.array(commandResultSchema).default([]),
  summary: z.string().default(""),
});

const finalSchema = z.looseObject({
  status: z.enum(["ready", "partial", "blocked", "empty"]).default("partial"),
  summary: z.string().default(""),
  roundsRun: z.number().int().default(0),
  selectedCount: z.number().int().default(0),
  materialChangeRounds: z.number().int().default(0),
  validationPassed: z.boolean().default(false),
  remainingRisks: z.array(z.string()).default([]),
  nextActions: z.array(z.string()).default([]),
  markdownBody: z.string().default(""),
});

const inputSchema = z.object({
  selector: z.enum(["plan", "ids", "label", "query", "ready", "all"]).default("plan"),
  planPath: z.string().nullable().default("docs/plans/fable/007-full-tool-socket-auth.md"),
  beadIds: z.array(z.string()).default([]),
  label: z.string().nullable().default(null),
  query: z.string().nullable().default(null),
  includeClosed: z.boolean().default(false),
  maxBeads: z.number().int().min(1).max(100).default(40),
  rounds: z.number().int().min(1).max(12).default(6),
  noMaterialChangeRoundsToStop: z.number().int().min(1).max(4).default(2),
  maxBeadConcurrency: z.number().int().min(1).max(20).default(6),
  reviewersPerBead: z.number().int().min(1).max(6).default(3),
  strict: z.boolean().default(true),
  dryRun: z.boolean().default(false),
  planContext: z.string().default("Use the selected beads as the source of truth. If a planPath is provided, selected beads should already embed the relevant source-plan decisions."),
});

const { Workflow, Task, Sequence, Parallel, MergeQueue, Loop, smithers, outputs } = createSmithers({
  input: inputSchema,
  inventory: inventorySchema,
  review: reviewSchema,
  synthesis: synthesisSchema,
  apply: applySchema,
  validation: validationSchema,
  final: finalSchema,
});

type CommandResult = z.infer<typeof commandResultSchema>;

const REVIEW_FOCI = [
  "contract completeness: outcome, observable success criteria, non-goals, failure behavior, closure evidence",
  "graph shape: split/merge decisions, parent closure contracts, dependencies, ready frontier, unsafe parallelism",
  "verification and readability: behavior tests, smoke commands, BV formatting, anchors without brittle edit scripts",
  "fresh-agent execution: Strong Agent Question Test, missing architecture/product decisions, implementation drift risk",
  "quality-gate triage: hard failures, warnings, long-child split test, validation theater",
  "implementation swarm readiness: file ownership risks, dependency order, closeout evidence",
];

const polishAgents = agents.beadsPolish;

function asArray(value: unknown): any[] {
  if (Array.isArray(value)) return value;
  if (value && typeof value === "object" && Array.isArray((value as any).issues)) return (value as any).issues;
  return [];
}

function asText(value: unknown): string {
  if (value == null) return "";
  if (typeof value === "string") return value;
  return JSON.stringify(value, null, 2);
}

function lower(value: unknown): string {
  return String(value ?? "").toLowerCase();
}

function beadSearchText(bead: any): string {
  return [
    bead.id,
    bead.title,
    bead.description,
    bead.external_ref,
    ...(Array.isArray(bead.labels) ? bead.labels : []),
  ].map(lower).join("\n");
}

function selectorSummary(input: z.infer<typeof inputSchema>): string {
  if (input.selector === "plan") return `planPath=${input.planPath ?? "(none)"}`;
  if (input.selector === "ids") return `ids=${input.beadIds.join(", ") || "(none)"}`;
  if (input.selector === "label") return `label=${input.label ?? "(none)"}`;
  if (input.selector === "query") return `query=${input.query ?? "(none)"}`;
  return input.selector;
}

function matchesSelector(bead: any, input: z.infer<typeof inputSchema>): boolean {
  if (!input.includeClosed && String(bead.status ?? "").toLowerCase() === "closed") return false;

  const text = beadSearchText(bead);
  if (input.selector === "all") return true;
  if (input.selector === "ready") {
    const labels = Array.isArray(bead.labels) ? bead.labels : [];
    return labels.includes("ready-for-agent") || Number(bead.dependency_count ?? 0) === 0;
  }
  if (input.selector === "ids") return input.beadIds.includes(String(bead.id ?? ""));
  if (input.selector === "label") {
    const labels = Array.isArray(bead.labels) ? bead.labels : [];
    return input.label ? labels.includes(input.label) : false;
  }
  if (input.selector === "query") {
    return input.query ? text.includes(input.query.toLowerCase()) : false;
  }
  if (input.selector === "plan") {
    const plan = input.planPath?.toLowerCase();
    if (!plan) return false;
    return lower(bead.external_ref).includes(plan) || text.includes(plan);
  }
  return false;
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
    command: argv.map((part) => part.includes(" ") ? JSON.stringify(part) : part).join(" "),
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

function buildGraphSummary(selectedBeads: any[], input: z.infer<typeof inputSchema>) {
  const selectedIds = new Set(selectedBeads.map((bead) => String(bead.id)));
  const lines = [
    `Selector: ${selectorSummary(input)}`,
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
  const maxBeads = input.maxBeads ?? 40;
  const list = await readJsonCommand(["br", "list", "--json"]);
  const issues = asArray(list);
  const selectedBase = issues
    .filter((bead) => matchesSelector(bead, input))
    .slice(0, maxBeads);

  const selectedBeads = [];
  for (const bead of selectedBase) {
    selectedBeads.push(compactBead((await showBead(String(bead.id))) ?? bead));
  }

  const warnings = [];
  if (selectedBeads.length === 0) warnings.push("No beads matched the selector.");
  if (selectedBase.length >= maxBeads) warnings.push(`Selection was capped at maxBeads=${maxBeads}.`);

  return {
    selectorSummary: selectorSummary(input),
    selectedCount: selectedBeads.length,
    selectedBeads,
    warnings,
    graphSummary: buildGraphSummary(selectedBeads, input),
  };
}

function reviewAgentsFor(count: number) {
  const pool = [...polishAgents];
  if (pool.length === 0) {
    throw new Error("beads-polish requires at least one configured polish agent.");
  }

  const reviewerCount = Math.max(1, count);
  return Array.from({ length: reviewerCount }, (_, index) => pool[index % pool.length]);
}

function reviewNeeds(beadId: string, reviewers: any[]) {
  return Object.fromEntries(reviewers.map((_, index) => [`review${index}`, `bead:${beadId}:review:${index}`]));
}

function reviewDeps(reviewers: any[]) {
  return Object.fromEntries(reviewers.map((_, index) => [`review${index}`, outputs.review]));
}

function synthesisNeeds(beads: any[]) {
  return Object.fromEntries(beads.map((bead: any, index: number) => [`bead${index}`, `bead:${bead.id}:synthesize`]));
}

function synthesisDeps(beads: any[]) {
  return Object.fromEntries(beads.map((_, index) => [`bead${index}`, outputs.synthesis]));
}

function applyTaskId(beadId: string) {
  return `apply:${beadId}`;
}

function latestConsecutiveNoMaterialChangeRounds(applyResults: any[], needed: number): boolean {
  const byIteration = new Map<number, boolean>();
  for (const result of applyResults) {
    const iteration = Number(result?.iteration ?? 0);
    byIteration.set(iteration, (byIteration.get(iteration) ?? false) || Boolean(result?.materialChanges));
  }

  const rounds = Array.from(byIteration.entries())
    .sort(([left], [right]) => left - right)
    .map(([, materialChanges]) => materialChanges);
  if (rounds.length < needed) return false;
  return rounds.slice(-needed).every((materialChanges) => !materialChanges);
}

function synthesizeSingleReview(bead: any, review: any) {
  const findings = Array.isArray(review?.findings) ? review.findings : [];
  const byCategory = (category: string) => findings
    .filter((finding: any) => finding?.category === category)
    .map((finding: any) => `${finding.summary}: ${finding.recommendation}`);
  const materialChangeRecommended = findings.some((finding: any) => [
    "same-contract-detail",
    "new-independent-behavior",
    "graph-correction",
  ].includes(String(finding?.category)));

  return {
    beadId: String(bead.id),
    title: String(bead.title ?? ""),
    verdict: review?.verdict ?? "needs-polish",
    score: review?.score ?? 24,
    materialChangeRecommended,
    rationale: [
      `Single-review synthesis from ${review?.reviewer ?? "reviewer"}.`,
      ...(Array.isArray(review?.hardFailures) && review.hardFailures.length > 0
        ? [`Hard failures: ${review.hardFailures.join("; ")}`]
        : []),
      ...(Array.isArray(review?.warnings) && review.warnings.length > 0
        ? [`Warnings: ${review.warnings.join("; ")}`]
        : []),
    ].join(" "),
    sameContractDetails: byCategory("same-contract-detail"),
    independentBehaviors: byCategory("new-independent-behavior"),
    graphCorrections: byCategory("graph-correction"),
    readabilityChanges: byCategory("readability-only"),
    brMutationPlan: findings
      .filter((finding: any) => finding?.category !== "no-op")
      .map((finding: any) => finding?.recommendation)
      .filter(Boolean),
    readyForAgent: Boolean(review?.readyForAgent),
  };
}

async function validateSelection(input: z.infer<typeof inputSchema>) {
  const currentInventory = await buildInventory(input);
  const beadIds = currentInventory.selectedBeads.map((bead: any) => String(bead.id));
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

  if (gate) {
    for (const id of beadIds) {
      const argv = ["python3", gate, "--id", id];
      if (input.strict) argv.push("--strict");
      commandResults.push(await runCommand(argv, 180_000));
    }
  } else {
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

  const qualityGateResults = commandResults.slice(3);
  const qualityGatePassed = qualityGateResults.length > 0 && qualityGateResults.every((result) => {
    if (result.exitCode === 0) return true;
    if (result.stdout.includes("0 error(s)") && result.stdout.includes("[WARNING]")) return true;
    return false;
  });
  const graphPlanAvailable = (commandResults[2]?.exitCode ?? 1) === 0;
  const passed = cyclesCount === 0 && qualityGatePassed && graphPlanAvailable;

  return {
    passed,
    cyclesCount,
    qualityGatePassed,
    graphPlanAvailable,
    commandResults,
    summary: passed
      ? `Selected beads passed cycle, graph, and local quality validation (${beadIds.length} current bead(s)); warning-only gate output is advisory.`
      : `Selected beads still need polishing (${beadIds.length} current bead(s)); inspect commandResults for cycle, graph, or quality-gate failures.`,
  };
}

function renderBeadLane(ctx: any, bead: any) {
  const reviewers = reviewAgentsFor(ctx.input.reviewersPerBead ?? 3);
  const beadText = JSON.stringify(bead, null, 2);
  const graphSummary = ctx.outputMaybe("inventory", { nodeId: "inventory", iteration: 0 })?.graphSummary ?? "";

  return (
    <Sequence key={`bead:${bead.id}`}>
      <Parallel maxConcurrency={reviewers.length}>
        {reviewers.map((agent, index) => (
          <Task
            key={`bead:${bead.id}:review:${index}`}
            id={`bead:${bead.id}:review:${index}`}
            output={outputs.review}
            agent={agent}
            continueOnFail
            timeoutMs={900_000}
            heartbeatTimeoutMs={180_000}
          >
            <ReviewPrompt
              focus={REVIEW_FOCI[index % REVIEW_FOCI.length]}
              planPath={ctx.input.planPath ?? ""}
              planContext={ctx.input.planContext}
              graphSummary={graphSummary}
              bead={beadText}
            />
          </Task>
        ))}
      </Parallel>
      {reviewers.length === 1 ? (
        <Task
          id={`bead:${bead.id}:synthesize`}
          output={outputs.synthesis}
          needs={reviewNeeds(bead.id, reviewers)}
          deps={reviewDeps(reviewers)}
        >
          {(deps: any) => synthesizeSingleReview(bead, Object.values(deps)[0])}
        </Task>
      ) : (
        <Task
          id={`bead:${bead.id}:synthesize`}
          output={outputs.synthesis}
          agent={polishAgents[0]}
          continueOnFail
          needs={reviewNeeds(bead.id, reviewers)}
          deps={reviewDeps(reviewers)}
          timeoutMs={600_000}
          heartbeatTimeoutMs={120_000}
        >
          {(deps: any) => (
            <SynthesizePrompt
              bead={beadText}
              graphSummary={graphSummary}
              reviews={JSON.stringify(Object.values(deps), null, 2)}
            />
          )}
        </Task>
      )}
    </Sequence>
  );
}

function renderApplyTask(ctx: any, inventory: any, bead: any) {
  return (
    <Task
      key={applyTaskId(bead.id)}
      id={applyTaskId(bead.id)}
      output={outputs.apply}
      agent={polishAgents[0]}
      continueOnFail
      needs={{ synthesis: `bead:${bead.id}:synthesize` }}
      deps={{ synthesis: outputs.synthesis }}
      timeoutMs={300_000}
      heartbeatTimeoutMs={90_000}
    >
      {(deps: any) => (
        <ApplyPrompt
          dryRun={ctx.input.dryRun ? "true" : "false"}
          selectorSummary={inventory.selectorSummary}
          planPath={ctx.input.planPath ?? ""}
          graphSummary={inventory.graphSummary}
          beadId={bead.id}
          synthesis={JSON.stringify(deps.synthesis, null, 2)}
        />
      )}
    </Task>
  );
}

export default smithers((ctx) => {
  const inventory = ctx.outputMaybe("inventory", { nodeId: "inventory", iteration: 0 });
  const selectedBeads = inventory?.selectedBeads ?? [];
  const applyResults = ctx.outputs.apply ?? [];
  const validationResults = ctx.outputs.validation ?? [];
  const lastValidation = validationResults.at(-1);
  const stopForNoMaterialChanges = latestConsecutiveNoMaterialChangeRounds(
    applyResults,
    ctx.input.noMaterialChangeRoundsToStop ?? 2,
  );
  const done = Boolean(lastValidation?.passed === true && stopForNoMaterialChanges);

  return (
    <Workflow name="beads-polish">
      <Sequence>
        <Task id="inventory" output={outputs.inventory}>
          {async () => buildInventory(ctx.input)}
        </Task>

        {inventory && selectedBeads.length === 0 ? (
          <Task id="final-empty" output={outputs.final}>
            {{
              status: "empty",
              summary: "No beads matched the selector.",
              roundsRun: 0,
              selectedCount: 0,
              materialChangeRounds: 0,
              validationPassed: false,
              remainingRisks: inventory.warnings ?? [],
              nextActions: ["Rerun with selector=ids, selector=query, selector=label, or a different planPath."],
              markdownBody: "# Beads Polish\n\nNo beads matched the selector.",
            }}
          </Task>
        ) : null}

        {inventory && selectedBeads.length > 0 ? (
          <Loop id="polish:rounds" until={done} maxIterations={ctx.input.rounds ?? 6} onMaxReached="return-last">
            <Sequence>
              <Parallel maxConcurrency={Math.min(ctx.input.maxBeadConcurrency ?? 6, selectedBeads.length)}>
                {selectedBeads.map((bead: any) => renderBeadLane(ctx, bead))}
              </Parallel>

              <MergeQueue id="beads:apply-queue" maxConcurrency={1}>
                {selectedBeads.map((bead: any) => renderApplyTask(ctx, inventory, bead))}
              </MergeQueue>

              <Task id="validation" output={outputs.validation}>
                {async () => validateSelection(ctx.input)}
              </Task>
            </Sequence>
          </Loop>
        ) : null}

        {inventory && selectedBeads.length > 0 && (done || validationResults.length >= (ctx.input.rounds ?? 6)) ? (
          <Task id="final" output={outputs.final} agent={polishAgents}>
            <FinalPrompt
              inventory={JSON.stringify(inventory, null, 2)}
              applyResults={JSON.stringify(applyResults, null, 2)}
              validationResults={JSON.stringify(validationResults, null, 2)}
            />
          </Task>
        ) : null}
      </Sequence>
    </Workflow>
  );
});
