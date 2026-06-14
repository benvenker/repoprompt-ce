// smithers-source: project
// smithers-metadata-version: 1
// smithers-display-name: Fable 008 Lane
// smithers-description: Serially run the existing implement workflow over ready Fable 008 task beads until the lane is done.
// smithers-tags: beads,fable,implementation,loop
/** @jsxImportSource smithers-orchestrator */
import { spawnSync } from "node:child_process";
import { createSmithers } from "smithers-orchestrator";
import { z } from "zod/v4";
import { agents } from "../agents";

const DEFAULT_BEAD_IDS = [
  "repoprompt-ce-fable-008-cancelling-state-9mo",
  "repoprompt-ce-fable-008-termination-cleanup-i27",
  "repoprompt-ce-fable-008-context-builder-spawn-x9u",
  "repoprompt-ce-fable-008-drift-check-2p6",
];

const inputSchema = z.object({
  beadIds: z.array(z.string()).default(DEFAULT_BEAD_IDS),
  implementMaxIterations: z.number().int().min(1).max(8).default(4),
  childMaxConcurrency: z.number().int().min(1).max(8).default(4),
  requireCleanTree: z.boolean().default(true),
  allowNoVerifyForKnownHostToolGap: z.boolean().default(false),
});

const frontierSchema = z.object({
  done: z.boolean(),
  blocked: z.boolean().default(false),
  beadId: z.string().nullable().default(null),
  beadTitle: z.string().nullable().default(null),
  readyCount: z.number().int().default(0),
  openTaskCount: z.number().int().default(0),
  cycleCount: z.number().int().default(0),
  gitStatus: z.string(),
  summary: z.string(),
});

const childRunSchema = z.object({
  beadId: z.string(),
  success: z.boolean(),
  command: z.string(),
  exitCode: z.number().int(),
  stdoutTail: z.string(),
  stderrTail: z.string(),
  summary: z.string(),
});

const finalizeSchema = z.object({
  beadId: z.string(),
  finalized: z.boolean(),
  commits: z.array(z.string()).default([]),
  beadClosed: z.boolean().default(false),
  validationEvidence: z.array(z.string()).default([]),
  summary: z.string(),
});

const finalSchema = z.object({
  done: z.boolean(),
  processedBeads: z.array(z.string()).default([]),
  summary: z.string(),
});

const { Workflow, Task, Sequence, Branch, Loop, smithers, outputs } = createSmithers({
  input: inputSchema,
  frontier: frontierSchema,
  childRun: childRunSchema,
  finalize: finalizeSchema,
  final: finalSchema,
});

type CommandResult = {
  status: number;
  stdout: string;
  stderr: string;
  command: string;
};

type BeadIssue = {
  id?: string;
  title?: string;
  status?: string;
  issue_type?: string;
};

type LaneInput = {
  beadIds: string[];
  implementMaxIterations: number;
  childMaxConcurrency: number;
  requireCleanTree: boolean;
  allowNoVerifyForKnownHostToolGap: boolean;
};

function normalizeInput(input: z.infer<typeof inputSchema>): LaneInput {
  return {
    beadIds: Array.isArray(input.beadIds) && input.beadIds.length > 0 ? input.beadIds : DEFAULT_BEAD_IDS,
    implementMaxIterations: typeof input.implementMaxIterations === "number" ? input.implementMaxIterations : 4,
    childMaxConcurrency: typeof input.childMaxConcurrency === "number" ? input.childMaxConcurrency : 4,
    requireCleanTree: input.requireCleanTree !== false,
    allowNoVerifyForKnownHostToolGap: input.allowNoVerifyForKnownHostToolGap === true,
  };
}

function tail(text: string, max = 6000): string {
  return text.length <= max ? text : text.slice(text.length - max);
}

function run(command: string, args: string[], maxBuffer = 64 * 1024 * 1024): CommandResult {
  const result = spawnSync(command, args, {
    cwd: process.cwd(),
    encoding: "utf8",
    maxBuffer,
  });
  return {
    status: result.status ?? 1,
    stdout: result.stdout ?? "",
    stderr: result.stderr ?? "",
    command: [command, ...args.map((arg) => JSON.stringify(arg))].join(" "),
  };
}

function requireOk(result: CommandResult): CommandResult {
  if (result.status !== 0) {
    throw new Error(`${result.command} exited ${result.status}\n${tail(result.stderr || result.stdout)}`);
  }
  return result;
}

function parseJson<T>(result: CommandResult): T {
  requireOk(result);
  return JSON.parse(result.stdout) as T;
}

function issuesFrom(value: unknown): BeadIssue[] {
  if (Array.isArray(value)) return value as BeadIssue[];
  if (value && typeof value === "object" && Array.isArray((value as { issues?: unknown }).issues)) {
    return (value as { issues: BeadIssue[] }).issues;
  }
  return [];
}

function cycleCount(value: unknown): number {
  if (Array.isArray(value)) return value.length;
  if (!value || typeof value !== "object") return 0;
  const object = value as { count?: unknown; cycles?: unknown };
  if (typeof object.count === "number") return object.count;
  if (Array.isArray(object.cycles)) return object.cycles.length;
  return 0;
}

function selectFrontier(input: LaneInput) {
  const status = requireOk(run("git", ["status", "--short", "--branch"])).stdout.trim();
  const dirtyLines = status
    .split("\n")
    .filter((line) => line.trim().length > 0 && !line.startsWith("##"));
  if (input.requireCleanTree && dirtyLines.length > 0) {
    throw new Error(`Working tree must be clean before selecting the next Fable 008 bead:\n${status}`);
  }

  const cycles = parseJson<unknown>(run("br", ["dep", "cycles", "--json"]));
  const cyclesFound = cycleCount(cycles);
  if (cyclesFound > 0) {
    throw new Error(`Beads dependency graph has ${cyclesFound} cycle(s); refusing to continue Fable 008 lane.`);
  }

  requireOk(run("bv", ["--robot-plan"]));

  const listArgs = ["list", "--all", "--json", "--limit", "0"];
  for (const beadId of input.beadIds) {
    listArgs.push("--id", beadId);
  }
  const listedTasks = issuesFrom(parseJson<unknown>(run("br", listArgs)));
  const listedById = new Map(listedTasks.map((issue) => [issue.id, issue]));
  const openTasks = input.beadIds
    .map((id) => listedById.get(id))
    .filter((issue): issue is BeadIssue => issue?.status === "open");

  const readyTasks = issuesFrom(parseJson<unknown>(run("br", [
    "ready",
    "--json",
    "--limit",
    "0",
    "--sort",
    "priority",
  ])));
  const readyIds = new Set(readyTasks.map((issue) => issue.id).filter((id): id is string => typeof id === "string"));
  const beadId = input.beadIds.find((id) => readyIds.has(id) && listedById.get(id)?.status === "open") ?? null;
  const bead = beadId ? listedById.get(beadId) : undefined;
  const done = openTasks.length === 0;
  const blocked = !done && beadId === null;
  return {
    done: done || blocked,
    blocked,
    beadId,
    beadTitle: bead?.title ?? null,
    readyCount: input.beadIds.filter((id) => readyIds.has(id) && listedById.get(id)?.status === "open").length,
    openTaskCount: openTasks.length,
    cycleCount: cyclesFound,
    gitStatus: status,
    summary: done
      ? "No open beads remain in the configured Fable 008 bead list."
      : blocked
        ? `${openTasks.length} configured Fable 008 bead(s) remain, but none are ready.`
        : `Next configured Fable 008 bead: ${beadId ?? "unknown"}`,
  };
}

function buildImplementPrompt(beadId: string, input: LaneInput): string {
  const noVerifyPolicy = input.allowNoVerifyForKnownHostToolGap
    ? "If commit preflight fails only because native host tools such as swift are missing, and Docker Swift validation plus staged secret scanning have passed for the same tree, this workflow authorizes --no-verify for that known host-tool gap. Report the gap in the finalizer output."
    : "If commit preflight fails because a host tool is missing, stop and report it; do not use --no-verify.";

  return `We are in ${process.cwd()} on the Fable 008 lane.

Goal: implement exactly one current ready Fable 008 bead through the existing implementation/review loop.

Current bead:
${beadId}

Hard constraints:
- Treat the bead as the execution contract.
- Do not work Plan 011. Plan 011 owns lifecycle edge-smoke coverage later.
- Do not implement downstream Fable 008 beads in this child run.
- Preserve the Plan 008 STOP/drift checks.
- Before edits, read AGENTS.md, run git status --short --branch, br dep cycles --json, bv --robot-plan, and br show ${beadId}.
- Use Docker Swift on Linux/VPS if native swift is unavailable:
  docker run --rm -v "$PWD":/src -w /src swift:6.2.4-noble swift build --product rpce-headless --scratch-path .build-linux
- Run the smallest validation required by the bead, using .build-linux/debug/rpce-headless for smokes when relevant.
- Do not add Plan 011 lifecycle smoke coverage.
- Leave Beads mutation and git finalization to the parent workflow finalizer. Do not close ${beadId} yourself unless the finalizer explicitly cannot run.

Commit/finalization policy for the parent finalizer:
${noVerifyPolicy}

Return the normal implement workflow JSON summary when the bead implementation is ready for finalization.`;
}

function runImplementWorkflow(beadId: string, input: LaneInput) {
  const childInput = {
    prompt: buildImplementPrompt(beadId, input),
    maxIterations: input.implementMaxIterations,
    onMaxReached: "fail",
  };
  const args = [
    "workflow",
    "run",
    "implement",
    "--input",
    JSON.stringify(childInput),
    "--max-concurrency",
    String(input.childMaxConcurrency),
  ];
  const result = run(".smithers/node_modules/.bin/smithers", args, 96 * 1024 * 1024);
  if (result.status !== 0) {
    throw new Error(`implement child failed for ${beadId}\n${tail(result.stderr || result.stdout, 12000)}`);
  }
  return {
    beadId,
    success: true,
    command: result.command,
    exitCode: result.status,
    stdoutTail: tail(result.stdout),
    stderrTail: tail(result.stderr),
    summary: `Existing implement workflow completed for ${beadId}.`,
  };
}

function finalizePrompt(
  beadId: string,
  childRun: z.infer<typeof childRunSchema>,
  input: LaneInput,
): string {
  const noVerifyPolicy = input.allowNoVerifyForKnownHostToolGap
    ? "You may use --no-verify only when the repo preflight fails solely because native host tools such as swift are missing and you have clean Docker Swift validation/guardrail evidence plus staged Gitleaks evidence for the exact staged tree."
    : "Do not use --no-verify. If repo preflight fails because a host tool is missing, stop and report the gap.";

  return `Finalize exactly this Fable 008 bead after a successful child implement workflow:
${beadId}

Child implement evidence:
- command: ${childRun.command}
- exitCode: ${childRun.exitCode}
- stdout tail:
${childRun.stdoutTail}
- stderr tail:
${childRun.stderrTail}

Finalizer contract:
- Read AGENTS.md and follow the repository contribution contract.
- Inspect git status and the diff. Stage only files intended for ${beadId}.
- Ensure the bead's required validation evidence exists. Reuse fresh Docker Swift evidence from the child run only if it applies to the exact tree; otherwise rerun the smallest required checks.
- Before committing, run .agents/skills/rpce-contribution-check/scripts/preflight.sh commit after staging.
- ${noVerifyPolicy}
- Commit the source/test/doc changes for ${beadId}.
- Close the bead with br close only after validation and commit evidence are available.
- Run br sync --flush-only after closing if needed.
- Commit the Beads metadata closeout separately if br mutates tracked files.
- Leave the working tree clean.
- Do not work Plan 011 and do not implement any downstream Fable 008 bead.

Return JSON matching the schema with commit ids, whether the bead was closed, validation evidence commands, and a short summary.`;
}

export default smithers((ctx) => {
  const input = normalizeInput(ctx.input);
  const frontiers = ctx.outputs.frontier ?? [];
  const childRuns = ctx.outputs.childRun ?? [];
  const finalizers = ctx.outputs.finalize ?? [];
  const latestFrontier = frontiers.at(-1);
  const latestChild = childRuns.at(-1);
  const latestFinalize = finalizers.at(-1);
  const beadId = latestFrontier?.beadId ?? null;
  const done = latestFrontier?.done === true;
  const needsChild = beadId !== null
    && !done
    && latestChild?.beadId !== beadId
    && latestFinalize?.beadId !== beadId;
  const needsFinalize = beadId !== null
    && !done
    && latestChild?.beadId === beadId
    && latestFinalize?.beadId !== beadId;
  const processedBeads = finalizers
    .filter((entry) => entry.finalized)
    .map((entry) => entry.beadId);

  return (
    <Workflow name="fable-008-lane">
      <Sequence>
        <Loop id="fable-008:loop" until={done} maxIterations={input.beadIds.length + 1} onMaxReached="fail">
          <Sequence>
            <Task id="frontier" output={outputs.frontier}>
              {() => selectFrontier(input)}
            </Task>
            <Branch
              if={needsChild}
              then={
                <Task id="run-implement" output={outputs.childRun} timeoutMs={14_400_000} heartbeatTimeoutMs={900_000}>
                  {() => runImplementWorkflow(beadId ?? "", input)}
                </Task>
              }
              else={null}
            />
            <Branch
              if={needsFinalize}
              then={needsFinalize && latestChild ? (
                <Task id="finalize" output={outputs.finalize} agent={agents.smartTool} timeoutMs={3_600_000} heartbeatTimeoutMs={900_000}>
                  {finalizePrompt(beadId ?? "", latestChild, input)}
                </Task>
              ) : null}
              else={null}
            />
          </Sequence>
        </Loop>
        <Task id="final" output={outputs.final}>
          {() => ({
            done,
            processedBeads,
            summary: done
              ? `Fable 008 lane loop finished. Processed ${processedBeads.length} bead(s).`
              : `Fable 008 lane stopped before completion. Processed ${processedBeads.length} bead(s).`,
          })}
        </Task>
      </Sequence>
    </Workflow>
  );
});
