// smithers-source: seeded
// smithers-display-name: Mission Kanban
/** @jsxImportSource smithers-orchestrator */
import { createSmithers } from "smithers-orchestrator";
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { basename, isAbsolute, relative, resolve } from "node:path";
import { z } from "zod/v4";
import { agents } from "../agents";
import ReadPlanPrompt from "../prompts/mission-kanban-read-plan.mdx";
import DraftTicketsPrompt from "../prompts/mission-kanban-draft-tickets.mdx";
import CheckAlignmentPrompt from "../prompts/mission-kanban-check-alignment.mdx";
import MaterializeTicketsPrompt from "../prompts/mission-kanban-materialize-tickets.mdx";
import ImplementTicketPrompt from "../prompts/mission-kanban-implement-ticket.mdx";
import ValidateTicketPrompt from "../prompts/mission-kanban-validate-ticket.mdx";
import ReviewTicketPrompt from "../prompts/mission-kanban-review-ticket.mdx";
import TicketResultPrompt from "../prompts/mission-kanban-ticket-result.mdx";
import IntegrateResultsPrompt from "../prompts/mission-kanban-integrate-results.mdx";
import FinalReviewFunctionalPrompt from "../prompts/mission-kanban-final-review-functional.mdx";
import FinalReviewValidationPrompt from "../prompts/mission-kanban-final-review-validation.mdx";
import FinalReviewArchitecturePrompt from "../prompts/mission-kanban-final-review-architecture.mdx";
import FinalSynthesisPrompt from "../prompts/mission-kanban-final-synthesis.mdx";
import WriteReportPrompt from "../prompts/mission-kanban-write-report.mdx";

const inputSchema = z.object({
  planPath: z.string().min(1, "planPath is required"),
  prompt: z.string().optional().nullable().default(null),
  maxTickets: z.number().int().min(7).default(7),
  maxConcurrency: z.number().int().min(1).default(3),
  baseBranch: z.string().optional().nullable().default(null),
  ticketBranchPrefix: z.string().default("mission"),
  overwriteTickets: z.boolean().default(false),
});

const runConfigSchema = z.object({
  summary: z.string(),
  planPath: z.string(),
  baseBranch: z.string(),
  ticketsDir: z.string(),
  maxTickets: z.number().int(),
  maxConcurrency: z.number().int(),
  ticketBranchPrefix: z.string(),
  overwriteTickets: z.boolean(),
});

const planSummarySchema = z.looseObject({
  summary: z.string(),
  planTitle: z.string(),
  implementationUnits: z.array(z.looseObject({})).default([]),
  requirements: z.array(z.string()).default([]),
  files: z.array(z.string()).default([]),
  validationCommands: z.array(z.string()).default([]),
  acceptanceExamples: z.array(z.string()).default([]),
  risks: z.array(z.string()).default([]),
});

const ticketSpecSchema = z.looseObject({
  id: z.string(),
  slug: z.string(),
  title: z.string(),
  summary: z.string(),
  sourceUnits: z.array(z.string()).default([]),
  requirements: z.array(z.string()).default([]),
  files: z.array(z.string()).default([]),
  validationCommands: z.array(z.string()).default([]),
  acceptanceCriteria: z.array(z.string()).default([]),
  dependencies: z.array(z.string()).default([]),
  risks: z.array(z.string()).default([]),
});

const ticketDraftSchema = z.looseObject({
  summary: z.string(),
  tickets: z.array(ticketSpecSchema).default([]),
  ticketCount: z.number().int().default(0),
  unitCoverageMap: z.record(z.string(), z.array(z.string())).default({}),
});

const alignmentCheckSchema = z.looseObject({
  summary: z.string(),
  passes: z.boolean(),
  missingUnits: z.array(z.string()).default([]),
  missingRequirements: z.array(z.string()).default([]),
  missingValidation: z.array(z.string()).default([]),
  missingAcceptanceExamples: z.array(z.string()).default([]),
  regenerationInstructions: z.string().default(""),
});

const materializedTicketSchema = z.looseObject({
  ticketId: z.string(),
  slug: z.string(),
  title: z.string(),
  path: z.string(),
  branch: z.string(),
});

const materializedTicketsSchema = z.looseObject({
  summary: z.string(),
  ticketFiles: z.array(materializedTicketSchema).default([]),
  writtenFiles: z.array(z.string()).default([]),
  skippedFiles: z.array(z.string()).default([]),
  archivedFiles: z.array(z.string()).default([]),
  errors: z.array(z.string()).default([]),
});

const ticketImplementationSchema = z.looseObject({
  summary: z.string(),
  ticketId: z.string(),
  branch: z.string(),
  worktreePath: z.string(),
  changedFiles: z.array(z.string()).default([]),
  implementationNotes: z.array(z.string()).default([]),
  risks: z.array(z.string()).default([]),
});

const ticketValidationSchema = z.looseObject({
  summary: z.string(),
  ticketId: z.string(),
  passed: z.boolean().default(false),
  commands: z.array(z.looseObject({
    command: z.string(),
    status: z.enum(["passed", "failed", "skipped"]).default("skipped"),
    summary: z.string().default(""),
  })).default([]),
  failures: z.array(z.string()).default([]),
  artifacts: z.array(z.string()).default([]),
});

const ticketReviewSchema = z.looseObject({
  summary: z.string(),
  ticketId: z.string(),
  approved: z.boolean().default(false),
  findings: z.array(z.string()).default([]),
  requiredFixes: z.array(z.string()).default([]),
  risks: z.array(z.string()).default([]),
});

const ticketResultSchema = z.looseObject({
  summary: z.string(),
  ticketId: z.string(),
  status: z.enum(["completed", "partial", "failed"]).default("partial"),
  branch: z.string(),
  changedFiles: z.array(z.string()).default([]),
  validationResults: z.array(z.any()).default([]),
  reviewFindings: z.array(z.any()).default([]),
  unresolvedRisks: z.array(z.string()).default([]),
});

const integrationResultSchema = z.looseObject({
  summary: z.string(),
  integratedBranches: z.array(z.string()).default([]),
  changedFiles: z.array(z.string()).default([]),
  validationResults: z.array(z.any()).default([]),
  reviewFindings: z.array(z.any()).default([]),
  unresolvedRisks: z.array(z.string()).default([]),
  integrationStatus: z.enum(["integrated", "partial", "blocked"]).default("partial"),
});

const finalReviewSchema = z.looseObject({
  summary: z.string(),
  satisfiesPlan: z.boolean().default(false),
  findings: z.array(z.string()).default([]),
  missingRequirements: z.array(z.string()).default([]),
  validationGaps: z.array(z.string()).default([]),
  risks: z.array(z.string()).default([]),
  followUpTickets: z.array(z.any()).default([]),
});

const finalSynthesisSchema = z.looseObject({
  summary: z.string(),
  satisfiesSourcePlan: z.boolean().default(false),
  ticketResults: z.array(z.any()).default([]),
  branches: z.array(z.string()).default([]),
  changedFiles: z.array(z.string()).default([]),
  validationResults: z.array(z.any()).default([]),
  reviewFindings: z.array(z.any()).default([]),
  unresolvedRisks: z.array(z.string()).default([]),
  followUpTickets: z.array(z.any()).default([]),
  decision: z.enum(["satisfied", "partial", "blocked"]).default("partial"),
});

const missionReportSchema = z.looseObject({
  summary: z.string(),
  reportPath: z.string(),
  satisfiesSourcePlan: z.boolean().default(false),
  followUpTickets: z.array(z.any()).default([]),
  unresolvedRisks: z.array(z.string()).default([]),
});

const { Workflow, Task, Sequence, Parallel, Loop, Worktree, MergeQueue, smithers, outputs } = createSmithers({
  input: inputSchema,
  runConfig: runConfigSchema,
  planSummary: planSummarySchema,
  ticketDraft: ticketDraftSchema,
  alignmentCheck: alignmentCheckSchema,
  materializedTickets: materializedTicketsSchema,
  ticketImplementation: ticketImplementationSchema,
  ticketValidation: ticketValidationSchema,
  ticketReview: ticketReviewSchema,
  ticketResult: ticketResultSchema,
  integrationResult: integrationResultSchema,
  finalReview: finalReviewSchema,
  finalSynthesis: finalSynthesisSchema,
  missionReport: missionReportSchema,
});

function repoRelative(path: string): string {
  return relative(process.cwd(), path).replaceAll("\\", "/");
}

function currentBranch(): string {
  try {
    return execFileSync("git", ["branch", "--show-current"], { cwd: process.cwd(), encoding: "utf8" }).trim() || "main";
  } catch {
    return "main";
  }
}

function normalizePlanPath(planPath: string): string {
  const absolute = isAbsolute(planPath) ? planPath : resolve(process.cwd(), planPath);
  if (!existsSync(absolute)) {
    throw new Error(`Plan file does not exist: ${planPath}`);
  }
  return repoRelative(absolute);
}

function validateExecutablePlan(planPath: string, content: string): void {
  const frontmatterMatch = content.match(/^---\n([\s\S]*?)\n---/);
  const frontmatter = frontmatterMatch?.[1] ?? "";
  const blockedFields = frontmatter
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => /^(status|superseded_reason)\s*:/.test(line));

  if (blockedFields.length > 0) {
    throw new Error(
      `Plan file is not an executable source plan: ${planPath} declares lifecycle metadata (${blockedFields.join(", ")}).`,
    );
  }

  const blockingPhrases = [
    /do not execute as written/i,
    /must not drive automation/i,
    /not approved for execution/i,
  ];
  const matchedPhrase = blockingPhrases.find((pattern) => pattern.test(content));
  if (matchedPhrase) {
    throw new Error(
      `Plan file is not an executable source plan: ${planPath} contains execution-blocking language (${matchedPhrase.source}).`,
    );
  }
}

function titleFromPlan(planPath: string, content: string): string {
  const heading = content.match(/^#\s+(.+)$/m)?.[1]?.trim();
  return heading || basename(planPath);
}

function cleanSlug(value: unknown, fallback: string): string {
  const slug = String(value ?? "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
  return slug || fallback;
}

function cleanPrefix(value: unknown): string {
  const prefix = String(value ?? "mission")
    .trim()
    .replace(/^\/+|\/+$/g, "")
    .replace(/[^A-Za-z0-9._/-]+/g, "-");
  return prefix || "mission";
}

function ticketBranch(runConfig: any, ticket: any): string {
  return `${runConfig?.ticketBranchPrefix ?? "mission"}/${cleanSlug(ticket?.slug ?? ticket?.ticketId, "ticket")}`;
}

function ticketLoopDone(ctx: any, slug: string): boolean {
  const validation = ctx.outputMaybe("ticketValidation", { nodeId: `ticket:${slug}:validate` });
  const review = ctx.outputMaybe("ticketReview", { nodeId: `ticket:${slug}:review` });
  return validation?.passed === true && review?.approved === true;
}

function ticketNeeds(ticketFiles: any[]): Record<string, string> {
  return Object.fromEntries(ticketFiles.map((ticket, index) => [`ticket${index}`, `ticket:${ticket.slug}:result`]));
}

function ticketDeps(ticketFiles: any[]): Record<string, typeof ticketResultSchema> {
  return Object.fromEntries(ticketFiles.map((_, index) => [`ticket${index}`, outputs.ticketResult]));
}

export default smithers((ctx) => {
  const runConfig = ctx.outputMaybe("runConfig", { nodeId: "resolveRunConfig" });
  const planSummary = ctx.outputMaybe("planSummary", { nodeId: "readSourcePlan" });
  const ticketDraft = ctx.outputMaybe("ticketDraft", { nodeId: "draftTickets" });
  const alignmentCheck = ctx.outputMaybe("alignmentCheck", { nodeId: "checkTicketAlignment" });
  const materializedTickets = ctx.outputMaybe("materializedTickets", { nodeId: "materializeTickets" });
  const integrationResult = ctx.outputMaybe("integrationResult", { nodeId: "integrateTicketResults" });
  const finalSynthesis = ctx.outputMaybe("finalSynthesis", { nodeId: "finalMissionSynthesis" });
  const ticketFiles = materializedTickets?.ticketFiles ?? [];

  return (
    <Workflow name="mission-kanban">
      <Sequence>
        <Task id="resolveRunConfig" output={outputs.runConfig}>
          {() => {
            const planPath = normalizePlanPath(ctx.input.planPath);
            const planContent = readFileSync(resolve(process.cwd(), planPath), "utf8");
            validateExecutablePlan(planPath, planContent);
            const baseBranch = ctx.input.baseBranch?.trim() || currentBranch();
            const maxTickets = Math.max(7, ctx.input.maxTickets ?? 7);
            const maxConcurrency = Math.max(1, ctx.input.maxConcurrency ?? 3);
            const ticketBranchPrefix = cleanPrefix(ctx.input.ticketBranchPrefix);
            return {
              summary: `Mission Kanban will materialize up to ${maxTickets} tickets from ${planPath} and branch from ${baseBranch}.`,
              planPath,
              baseBranch,
              ticketsDir: ".smithers/tickets",
              maxTickets,
              maxConcurrency,
              ticketBranchPrefix,
              overwriteTickets: ctx.input.overwriteTickets ?? false,
            };
          }}
        </Task>

        {runConfig ? (
          <Task id="readSourcePlan" output={outputs.planSummary} agent={agents.smartTool}>
            {() => {
              const absolute = resolve(process.cwd(), runConfig.planPath);
              const content = readFileSync(absolute, "utf8");
              return (
                <ReadPlanPrompt
                  runConfig={runConfig}
                  plan={{
                    path: runConfig.planPath,
                    title: titleFromPlan(runConfig.planPath, content),
                    content,
                  }}
                  operatorPrompt={ctx.input.prompt}
                />
              );
            }}
          </Task>
        ) : null}

        {planSummary ? (
          <Loop
            id="ticket-generation-alignment"
            until={alignmentCheck?.passes === true}
            maxIterations={3}
            onMaxReached="fail"
          >
            <Sequence>
              <Task id="draftTickets" output={outputs.ticketDraft} agent={agents.smart}>
                <DraftTicketsPrompt
                  runConfig={runConfig}
                  planSummary={planSummary}
                  previousAlignment={alignmentCheck}
                  operatorPrompt={ctx.input.prompt}
                />
              </Task>
              <Task
                id="checkTicketAlignment"
                output={outputs.alignmentCheck}
                agent={agents.cheapFast}
                needs={{ ticketDraft: "draftTickets" }}
                deps={{ ticketDraft: outputs.ticketDraft }}
              >
                {(deps: any) => (
                  <CheckAlignmentPrompt
                    planSummary={planSummary}
                    ticketDraft={deps.ticketDraft}
                    maxTickets={runConfig?.maxTickets ?? ctx.input.maxTickets}
                  />
                )}
              </Task>
            </Sequence>
          </Loop>
        ) : null}

        {ticketDraft && alignmentCheck?.passes === true ? (
          <Task id="materializeTickets" output={outputs.materializedTickets} agent={agents.smartTool}>
            <MaterializeTicketsPrompt
              runConfig={runConfig}
              ticketDraft={ticketDraft}
              alignmentCheck={alignmentCheck}
            />
          </Task>
        ) : null}

        {runConfig && ticketFiles.length > 0 ? (
          <Parallel maxConcurrency={runConfig.maxConcurrency}>
            {ticketFiles.map((ticket: any) => {
              const slug = cleanSlug(ticket.slug, ticket.ticketId);
              const branch = ticketBranch(runConfig, ticket);
              const worktreePath = `.worktrees/mission-${slug}`;
              const done = ticketLoopDone(ctx, slug);
              return (
                <Worktree
                  key={slug}
                  id={`ticket-worktree-${slug}`}
                  path={worktreePath}
                  branch={branch}
                  baseBranch={runConfig.baseBranch}
                >
                  <Sequence>
                    <Loop
                      id={`ticket-implement-validate-review-${slug}`}
                      until={done}
                      maxIterations={3}
                      onMaxReached="return-last"
                    >
                      <Sequence>
                        <Task
                          id={`ticket:${slug}:implement`}
                          output={outputs.ticketImplementation}
                          agent={agents.cheapExecution}
                          timeoutMs={3_600_000}
                          heartbeatTimeoutMs={900_000}
                          continueOnFail
                        >
                          <ImplementTicketPrompt
                            runConfig={runConfig}
                            planSummary={planSummary}
                            ticket={ticket}
                            branch={branch}
                            worktreePath={worktreePath}
                            validation={ctx.outputMaybe("ticketValidation", { nodeId: `ticket:${slug}:validate` })}
                            review={ctx.outputMaybe("ticketReview", { nodeId: `ticket:${slug}:review` })}
                          />
                        </Task>
                        <Task
                          id={`ticket:${slug}:validate`}
                          output={outputs.ticketValidation}
                          agent={agents.smartTool}
                          needs={{ implementation: `ticket:${slug}:implement` }}
                          deps={{ implementation: outputs.ticketImplementation }}
                          timeoutMs={1_800_000}
                          heartbeatTimeoutMs={600_000}
                          continueOnFail
                        >
                          {(deps: any) => (
                            <ValidateTicketPrompt
                              runConfig={runConfig}
                              planSummary={planSummary}
                              ticket={ticket}
                              implementation={deps.implementation}
                            />
                          )}
                        </Task>
                        <Task
                          id={`ticket:${slug}:review`}
                          output={outputs.ticketReview}
                          agent={agents.smartTool}
                          needs={{
                            implementation: `ticket:${slug}:implement`,
                            validation: `ticket:${slug}:validate`,
                          }}
                          deps={{
                            implementation: outputs.ticketImplementation,
                            validation: outputs.ticketValidation,
                          }}
                          timeoutMs={1_800_000}
                          heartbeatTimeoutMs={600_000}
                          continueOnFail
                        >
                          {(deps: any) => (
                            <ReviewTicketPrompt
                              runConfig={runConfig}
                              planSummary={planSummary}
                              ticket={ticket}
                              implementation={deps.implementation}
                              validation={deps.validation}
                            />
                          )}
                        </Task>
                      </Sequence>
                    </Loop>
                    <Task
                      id={`ticket:${slug}:result`}
                      output={outputs.ticketResult}
                      agent={agents.cheapFast}
                      needs={{
                        implementation: `ticket:${slug}:implement`,
                        validation: `ticket:${slug}:validate`,
                        review: `ticket:${slug}:review`,
                      }}
                      deps={{
                        implementation: outputs.ticketImplementation,
                        validation: outputs.ticketValidation,
                        review: outputs.ticketReview,
                      }}
                      continueOnFail
                    >
                      {(deps: any) => (
                        <TicketResultPrompt
                          runConfig={runConfig}
                          ticket={ticket}
                          branch={branch}
                          implementation={deps.implementation}
                          validation={deps.validation}
                          review={deps.review}
                        />
                      )}
                    </Task>
                  </Sequence>
                </Worktree>
              );
            })}
          </Parallel>
        ) : null}

        {runConfig && ticketFiles.length > 0 ? (
          <MergeQueue id="integrate-ticket-results" maxConcurrency={1}>
            <Task
              id="integrateTicketResults"
              output={outputs.integrationResult}
              agent={agents.smartTool}
              needs={ticketNeeds(ticketFiles)}
              deps={ticketDeps(ticketFiles)}
              timeoutMs={3_600_000}
              heartbeatTimeoutMs={900_000}
              continueOnFail
            >
              {(deps: any) => (
                <IntegrateResultsPrompt
                  runConfig={runConfig}
                  planSummary={planSummary}
                  materializedTickets={materializedTickets}
                  ticketResults={Object.values(deps)}
                />
              )}
            </Task>
          </MergeQueue>
        ) : null}

        {integrationResult ? (
          <Parallel maxConcurrency={3}>
            <Task id="finalReviewerA" output={outputs.finalReview} agent={agents.smartTool} continueOnFail>
              <FinalReviewFunctionalPrompt
                runConfig={runConfig}
                planSummary={planSummary}
                materializedTickets={materializedTickets}
                integrationResult={integrationResult}
                ticketResults={ctx.outputs.ticketResult ?? []}
              />
            </Task>
            <Task id="finalReviewerB" output={outputs.finalReview} agent={agents.smartTool} continueOnFail>
              <FinalReviewValidationPrompt
                runConfig={runConfig}
                planSummary={planSummary}
                materializedTickets={materializedTickets}
                integrationResult={integrationResult}
                ticketResults={ctx.outputs.ticketResult ?? []}
              />
            </Task>
            <Task id="finalReviewerC" output={outputs.finalReview} agent={agents.smartTool} continueOnFail>
              <FinalReviewArchitecturePrompt
                runConfig={runConfig}
                planSummary={planSummary}
                materializedTickets={materializedTickets}
                integrationResult={integrationResult}
                ticketResults={ctx.outputs.ticketResult ?? []}
              />
            </Task>
          </Parallel>
        ) : null}

        {integrationResult ? (
          <Task
            id="finalMissionSynthesis"
            output={outputs.finalSynthesis}
            agent={agents.smart}
            needs={{
              functional: "finalReviewerA",
              validation: "finalReviewerB",
              architecture: "finalReviewerC",
            }}
            deps={{
              functional: outputs.finalReview,
              validation: outputs.finalReview,
              architecture: outputs.finalReview,
            }}
          >
            {(deps: any) => (
              <FinalSynthesisPrompt
                runConfig={runConfig}
                planSummary={planSummary}
                materializedTickets={materializedTickets}
                integrationResult={integrationResult}
                ticketResults={ctx.outputs.ticketResult ?? []}
                reviews={[deps.functional, deps.validation, deps.architecture]}
              />
            )}
          </Task>
        ) : null}

        {finalSynthesis ? (
          <Task id="writeMissionReport" output={outputs.missionReport} agent={agents.smartTool}>
            <WriteReportPrompt
              runConfig={runConfig}
              planSummary={planSummary}
              materializedTickets={materializedTickets}
              integrationResult={integrationResult}
              finalSynthesis={finalSynthesis}
            />
          </Task>
        ) : null}
      </Sequence>
    </Workflow>
  );
});
