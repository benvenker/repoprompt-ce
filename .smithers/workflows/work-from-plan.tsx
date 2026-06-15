// smithers-source: local
// smithers-metadata-version: 1
// smithers-display-name: Work From Plan
// smithers-description: Execute a repository plan document as an immutable decision artifact.
// smithers-tags: planning, implementation, review
/** @jsxImportSource smithers-orchestrator */
import { createSmithers } from "smithers-orchestrator";
import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { basename, extname, isAbsolute, relative, resolve } from "node:path";
import { z } from "zod/v4";
import { agents } from "../agents";
import { ValidationLoop, implementOutputSchema, validateOutputSchema } from "../components/ValidationLoop";
import { reviewOutputSchema } from "../components/Review";
import ManifestPrompt from "../prompts/work-from-plan-manifest.mdx";
import KnowledgePrompt from "../prompts/work-from-plan-knowledge.mdx";

const inputSchema = z.object({
  planPath: z.string().nullable().default(null),
  prompt: z.string().default(""),
  maxIterations: z.number().int().min(1).max(8).default(4),
  requireManifestApproval: z.boolean().default(false),
  commit: z.boolean().default(false),
  onMaxReached: z.enum(["fail", "return-last"]).default("fail"),
});

const resolvedPlanSchema = z.object({
  planPath: z.string(),
  source: z.enum(["input", "latest"]),
  title: z.string(),
  content: z.string(),
  lineCount: z.number().int().nonnegative(),
});

const manifestUnitSchema = z.object({
  id: z.string(),
  title: z.string(),
  goal: z.string(),
  files: z.array(z.string()).default([]),
  dependencies: z.array(z.string()).default([]),
  executionNote: z.string().nullable().default(null),
  testScenarios: z.array(z.string()).default([]),
  verification: z.array(z.string()).default([]),
  prompt: z.string(),
});

const manifestSchema = z.looseObject({
  summary: z.string(),
  executionKind: z.enum(["code", "knowledge-work", "unknown"]),
  planPath: z.string(),
  requirements: z.array(z.string()).default([]),
  scopeBoundaries: z.array(z.string()).default([]),
  deferredQuestions: z.array(z.string()).default([]),
  units: z.array(manifestUnitSchema).default([]),
  validationPlan: z.array(z.string()).default([]),
  commitPolicy: z.string(),
  implementationPrompt: z.string(),
});

const approvalSchema = z.object({
  approved: z.boolean(),
  note: z.string().nullable(),
  decidedBy: z.string().nullable(),
  decidedAt: z.string().nullable(),
});

const knowledgeResultSchema = z.looseObject({
  summary: z.string(),
  artifacts: z.array(z.string()).default([]),
  validation: z.array(z.string()).default([]),
  unresolvedQuestions: z.array(z.string()).default([]),
});

const finalSchema = z.object({
  summary: z.string(),
  planPath: z.string(),
  executionKind: z.string(),
  status: z.enum(["completed", "partial", "blocked"]),
});

const { Workflow, Task, Sequence, Branch, Approval, smithers, outputs } = createSmithers({
  input: inputSchema,
  resolvedPlan: resolvedPlanSchema,
  manifest: manifestSchema,
  approval: approvalSchema,
  implement: implementOutputSchema,
  validate: validateOutputSchema,
  review: reviewOutputSchema,
  knowledgeResult: knowledgeResultSchema,
  final: finalSchema,
});

function repoRelative(path: string): string {
  return relative(process.cwd(), path).replaceAll("\\", "/");
}

function findLatestPlan(): string {
  const plansDir = resolve(process.cwd(), "docs/plans");
  const candidates = readdirSync(plansDir)
    .filter((name) => [".md", ".html"].includes(extname(name)))
    .map((name) => resolve(plansDir, name))
    .filter((path) => statSync(path).isFile())
    .sort((a, b) => statSync(b).mtimeMs - statSync(a).mtimeMs);

  if (candidates.length === 0) {
    throw new Error("No plan found under docs/plans/*.md or docs/plans/*.html");
  }

  return repoRelative(candidates[0]);
}

function resolvePlanPath(input: string | null): { planPath: string; source: "input" | "latest" } {
  const trimmed = input?.trim();
  if (!trimmed) {
    return { planPath: findLatestPlan(), source: "latest" };
  }

  const absolute = isAbsolute(trimmed) ? trimmed : resolve(process.cwd(), trimmed);
  if (!existsSync(absolute)) {
    throw new Error(`Plan file does not exist: ${trimmed}`);
  }

  return { planPath: repoRelative(absolute), source: "input" };
}

function titleFromPlan(planPath: string, content: string): string {
  const frontmatterTitle = content.match(/^title:\s*["']?(.+?)["']?\s*$/m)?.[1]?.trim();
  const heading = content.match(/^#\s+(.+)$/m)?.[1]?.trim();
  return frontmatterTitle || heading || basename(planPath);
}

function buildFeedback(ctx: any): { feedback: string | null; done: boolean } {
  const validate = ctx.outputMaybe("validate", { nodeId: "plan-code:validate" });
  const reviews = ctx.outputs.review ?? [];

  const hasValidated = validate !== undefined;
  const validationPassed = hasValidated && validate.allPassed !== false;
  const anyApproved = reviews.length > 0 && reviews.some((review: any) => review.approved === true);
  const done = validationPassed && anyApproved;

  if (!hasValidated) {
    return { feedback: null, done: false };
  }

  const parts: string[] = [];
  if (!validationPassed && validate.failingSummary) {
    parts.push(`VALIDATION FAILED:\n${validate.failingSummary}`);
  }

  for (const review of reviews) {
    if (review.approved === false) {
      parts.push(`REVIEWER REJECTED:\n${review.feedback}`);
      for (const issue of review.issues ?? []) {
        parts.push(`  [${issue.severity}] ${issue.title}: ${issue.description}${issue.file ? ` (${issue.file})` : ""}`);
      }
    }
  }

  return {
    feedback: parts.length > 0 ? parts.join("\n\n") : null,
    done,
  };
}

function buildCodePrompt(manifest: any, operatorPrompt: string, commit: boolean): string {
  return [
    "Execute this plan manifest serially in the current repository.",
    "Read AGENTS.md first and follow the repository validation contract.",
    "Treat the plan as immutable: do not edit the plan body or use legacy checkboxes/status fields as progress state.",
    "Preserve plan unit IDs, dependencies, execution notes, scope boundaries, deferred questions, test scenarios, and verification criteria in your work summary.",
    "Run the smallest repo-appropriate validation after meaningful changes. Fix failures before proceeding to later units.",
    "Do not optimize for fake agents. Fake or sleeping agents are deterministic test fixtures only when the plan explicitly calls for them.",
    commit
      ? "Commit mode is enabled. Stage only intended files, run the repo-local contribution preflight in commit mode after staging, and commit only after validation passes."
      : "Commit mode is disabled. Do not stage files or commit.",
    operatorPrompt.trim() ? `Operator note:\n${operatorPrompt.trim()}` : null,
    `Execution manifest:\n${JSON.stringify(manifest, null, 2)}`,
  ].filter(Boolean).join("\n\n---\n\n");
}

export default smithers((ctx) => {
  const resolvedPlan = ctx.outputMaybe("resolvedPlan", { nodeId: "resolve-plan" });
  const manifest = ctx.outputMaybe("manifest", { nodeId: "build-manifest" });
  const approval = ctx.outputMaybe("approval", { nodeId: "approve-manifest" });
  const knowledgeResult = ctx.outputMaybe("knowledgeResult", { nodeId: "knowledge-work" });
  const { feedback, done } = buildFeedback(ctx);

  const manifestApproved = manifest !== undefined && (!ctx.input.requireManifestApproval || approval?.approved === true);
  const codeManifest = manifestApproved && manifest?.executionKind === "code";
  const knowledgeManifest = manifestApproved && manifest?.executionKind === "knowledge-work";
  const unknownManifest = manifestApproved && manifest?.executionKind === "unknown";

  return (
    <Workflow name="work-from-plan">
      <Sequence>
        <Task id="resolve-plan" output={outputs.resolvedPlan}>
          {async () => {
            const { planPath, source } = resolvePlanPath(ctx.input.planPath);
            const absolute = resolve(process.cwd(), planPath);
            const content = readFileSync(absolute, "utf8");
            return {
              planPath,
              source,
              title: titleFromPlan(planPath, content),
              content,
              lineCount: content.split(/\r?\n/).length,
            };
          }}
        </Task>

        {resolvedPlan ? (
          <Task id="build-manifest" output={outputs.manifest} agent={agents.smartTool}>
            <ManifestPrompt
              plan={resolvedPlan}
              operatorPrompt={ctx.input.prompt}
              commit={ctx.input.commit}
            />
          </Task>
        ) : null}

        <Branch
          if={manifest !== undefined && ctx.input.requireManifestApproval}
          then={
            <Approval
              id="approve-manifest"
              output={outputs.approval}
              request={{
                title: `Approve execution manifest for ${manifest?.planPath ?? "plan"}`,
                summary: manifest?.summary ?? "Review the parsed execution manifest before implementation begins.",
              }}
            />
          }
          else={null}
        />

        {knowledgeManifest ? (
          <Task id="knowledge-work" output={outputs.knowledgeResult} agent={agents.smartTool}>
            <KnowledgePrompt manifest={manifest} operatorPrompt={ctx.input.prompt} />
          </Task>
        ) : null}

        {codeManifest ? (
          <ValidationLoop
            idPrefix="plan-code"
            prompt={buildCodePrompt(manifest, ctx.input.prompt, ctx.input.commit)}
            implementAgents={agents.smart}
            validateAgents={agents.cheapFast}
            reviewAgents={agents.smart}
            feedback={feedback}
            done={done}
            maxIterations={ctx.input.maxIterations}
            onMaxReached={ctx.input.onMaxReached}
          />
        ) : null}

        {knowledgeResult ? (
          <Task id="final" output={outputs.final}>
            {{
              summary: knowledgeResult.summary,
              planPath: manifest?.planPath ?? resolvedPlan?.planPath ?? "",
              executionKind: "knowledge-work",
              status: knowledgeResult.unresolvedQuestions?.length ? "partial" : "completed",
            }}
          </Task>
        ) : null}

        {unknownManifest ? (
          <Task id="final-unknown" output={outputs.final}>
            {{
              summary: manifest?.summary ?? "Plan could not be classified into an executable manifest.",
              planPath: manifest?.planPath ?? resolvedPlan?.planPath ?? "",
              executionKind: "unknown",
              status: "blocked",
            }}
          </Task>
        ) : null}

        {done ? (
          <Task id="final-code" output={outputs.final}>
            {{
              summary: `Completed code execution for ${manifest?.planPath ?? resolvedPlan?.planPath ?? "plan"}.`,
              planPath: manifest?.planPath ?? resolvedPlan?.planPath ?? "",
              executionKind: manifest?.executionKind ?? "code",
              status: "completed",
            }}
          </Task>
        ) : null}
      </Sequence>
    </Workflow>
  );
});
