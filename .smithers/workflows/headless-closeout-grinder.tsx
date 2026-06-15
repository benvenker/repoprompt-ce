// smithers-source: local
// smithers-metadata-version: 1
// smithers-display-name: Headless Closeout Grinder
// smithers-description: Iterate CE code review, scoped fixes, and bounded headless validation until no P0/P1/P2 findings remain.
// smithers-tags: review,implementation,headless
/** @jsxImportSource smithers-orchestrator */
import { createSmithers } from "smithers-orchestrator";
import { z } from "zod/v4";
import { agents } from "../agents";
import EstablishScopePrompt from "../prompts/headless-closeout-establish-scope.mdx";
import CeReviewPrompt from "../prompts/headless-closeout-ce-review.mdx";
import FixPlanPrompt from "../prompts/headless-closeout-fix-plan.mdx";
import ApplyFixesPrompt from "../prompts/headless-closeout-apply-fixes.mdx";
import ValidationPrompt from "../prompts/headless-closeout-validation.mdx";
import LandingPacketPrompt from "../prompts/headless-closeout-landing-packet.mdx";

const DEFAULT_CLOSEOUT_PLAN = "docs/plans/2026-06-15-002-fix-headless-timeout-observability-closeout-plan.md";
const DEFAULT_SOURCE_PLANS = [
  "docs/plans/2026-06-15-001-fix-context-builder-async-results-plan.md",
  "docs/plans/2026-06-15-001-fix-headless-timeout-observability-plan.md",
];
const CE_CODE_REVIEW_SKILL =
  "/home/ben/.codex/plugins/cache/compound-engineering-plugin/compound-engineering/3.12.0/skills/ce-code-review/SKILL.md";

const severitySchema = z.enum(["P0", "P1", "P2", "P3", "nit"]);

const findingSchema = z.looseObject({
  id: z.string(),
  severity: severitySchema,
  title: z.string(),
  file: z.string().nullable().default(null),
  line: z.number().int().positive().nullable().default(null),
  actionable: z.boolean().default(false),
  source: z.string().default("ce-code-review"),
  evidence: z.string().nullable().default(null),
  recommendation: z.string().nullable().default(null),
});

const reviewResultSchema = z.object({
  status: z.string().nullable().default(null),
  verdict: z.string().nullable().default(null),
  artifact_path: z.string().nullable().default(null),
  coverage_summary: z.string().nullable().default(null),
  requirement_summary: z.array(z.string()).default([]),
  residual_risks: z.array(z.string()).default([]),
  testing_gaps: z.array(z.string()).default([]),
  notes: z.array(z.string()).default([]),
});

const inputSchema = z.object({
  prompt: z.string().default(""),
  maxIterations: z.number().int().positive().max(8).default(3),
  closeoutPlanPath: z.string().default(DEFAULT_CLOSEOUT_PLAN),
  sourcePlanPaths: z.array(z.string()).default(DEFAULT_SOURCE_PLANS),
  blockingSeverities: z.array(severitySchema).default(["P0", "P1", "P2"]),
  validationProfile: z.string().default("headless-linux-docker-bounded"),
});

const scopeSchema = z.looseObject({
  summary: z.string(),
  closeoutPlanPath: z.string(),
  sourcePlanPaths: z.array(z.string()),
  ceCodeReviewSkill: z.string(),
  gitStatus: z.string(),
  intendedScope: z.string(),
  candidateFiles: z.array(z.string()).default([]),
  approvalGatedActionsDetected: z.array(z.string()).default([]),
});

const reviewSchema = z.looseObject({
  summary: z.string(),
  status: z.string().default("complete"),
  verdict: z.string().nullable().default(null),
  rawReview: z.string().nullable().default(null),
  reviewResult: reviewResultSchema.nullable().default(null),
  findings: z.array(findingSchema).default([]),
  actionableFindings: z.array(findingSchema).default([]),
  parseable: z.boolean().default(true),
  malformedReason: z.string().nullable().default(null),
});

const normalizedReviewSchema = z.looseObject({
  summary: z.string(),
  allFindings: z.array(findingSchema).default([]),
  blockingFindings: z.array(findingSchema).default([]),
  nonBlockingFindings: z.array(findingSchema).default([]),
  malformedReview: z.boolean().default(false),
  completionBlocked: z.boolean().default(false),
  reviewDigest: z.string(),
});

const fixPlanSchema = z.looseObject({
  summary: z.string(),
  targetFiles: z.array(z.string()).default([]),
  fixPlan: z.string(),
  nonGoals: z.array(z.string()).default([]),
});

const fixResultSchema = z.looseObject({
  summary: z.string(),
  changedFiles: z.array(z.string()).default([]),
  resolvedFindingIds: z.array(z.string()).default([]),
  unresolvedFindingIds: z.array(z.string()).default([]),
  newRisks: z.array(z.string()).default([]),
  reservationsUsed: z.boolean().default(false),
  reservationsReleased: z.boolean().default(false),
});

const validationSchema = z.looseObject({
  summary: z.string(),
  commands: z.array(z.string()).default([]),
  dockerBuildPassed: z.boolean().nullable().default(null),
  smokePassed: z.boolean().nullable().default(null),
  validationEvidence: z.array(z.string()).default([]),
  hostToolGaps: z.array(z.string()).default([]),
  validationBlocked: z.boolean().default(false),
});

const landingPacketSchema = z.looseObject({
  summary: z.string(),
  resolvedFindings: z.array(z.string()).default([]),
  validationEvidence: z.array(z.string()).default([]),
  residualRisks: z.array(z.string()).default([]),
  intendedFiles: z.array(z.string()).default([]),
  unresolvedBlockers: z.array(findingSchema).default([]),
  commitReady: z.boolean(),
  noFilesStaged: z.boolean(),
  noCommitMade: z.boolean(),
});

const { Workflow, Task, Sequence, Branch, Loop, smithers, outputs } = createSmithers({
  input: inputSchema,
  scope: scopeSchema,
  review: reviewSchema,
  normalizedReview: normalizedReviewSchema,
  fixPlan: fixPlanSchema,
  fixResult: fixResultSchema,
  validation: validationSchema,
  landingPacket: landingPacketSchema,
});

function asArray(value: unknown): any[] {
  return Array.isArray(value) ? value : [];
}

function normalizeSeverity(value: unknown): "P0" | "P1" | "P2" | "P3" | "nit" {
  return value === "P0" || value === "P1" || value === "P2" || value === "P3" || value === "nit" ? value : "P3";
}

function normalizeFinding(value: any, index: number, actionableDefault: boolean): z.infer<typeof findingSchema> {
  const line = typeof value?.line === "number" && Number.isFinite(value.line) && value.line > 0 ? Math.floor(value.line) : null;
  const file = typeof value?.file === "string" && value.file.length > 0 ? value.file : null;
  const title =
    typeof value?.title === "string" && value.title.length > 0
      ? value.title
      : typeof value?.issue === "string" && value.issue.length > 0
        ? value.issue
        : `Review finding ${index + 1}`;

  return {
    id: typeof value?.id === "string" && value.id.length > 0 ? value.id : `finding-${index + 1}`,
    severity: normalizeSeverity(value?.severity),
    title,
    file,
    line,
    actionable: typeof value?.actionable === "boolean" ? value.actionable : actionableDefault,
    source: typeof value?.source === "string" ? value.source : "ce-code-review",
    evidence: typeof value?.evidence === "string" ? value.evidence : null,
    recommendation:
      typeof value?.recommendation === "string"
        ? value.recommendation
        : typeof value?.suggested_fix === "string"
          ? value.suggested_fix
          : null,
  };
}

function normalizeReview(review: any, blockingSeverities: string[]): z.infer<typeof normalizedReviewSchema> {
  if (!review || review.parseable === false || review.status === "failed") {
    const blocker = {
      id: "malformed-review-json",
      severity: "P1" as const,
      title: "ce-code-review result was missing or malformed",
      file: null,
      line: null,
      actionable: true,
      source: "workflow",
      evidence: review?.malformedReason ?? review?.summary ?? "No parseable CE review result was produced.",
      recommendation: "Rerun or repair the CE review step before declaring closeout complete.",
    };
    return {
      summary: "Review output could not be trusted; treating as a P1 blocker.",
      allFindings: [blocker],
      blockingFindings: [blocker],
      nonBlockingFindings: [],
      malformedReview: true,
      completionBlocked: true,
      reviewDigest: blocker.evidence ?? blocker.title,
    };
  }

  const source = review.reviewResult ?? review;
  const actionable = asArray(source?.actionable_findings ?? source?.actionableFindings ?? review.actionableFindings).map((finding, index) =>
    normalizeFinding(finding, index, true),
  );
  const all = asArray(source?.findings ?? review.findings).map((finding, index) => normalizeFinding(finding, index, false));
  const merged = [...actionable, ...all.filter((finding) => !actionable.some((item) => item.id === finding.id))];
  const blocking = merged.filter((finding) => finding.actionable && blockingSeverities.includes(finding.severity));
  const nonBlocking = merged.filter((finding) => !blocking.includes(finding));

  return {
    summary: blocking.length
      ? `${blocking.length} actionable blocking finding(s) remain.`
      : "No actionable P0/P1/P2 findings remain in the latest CE review.",
    allFindings: merged,
    blockingFindings: blocking,
    nonBlockingFindings: nonBlocking,
    malformedReview: false,
    completionBlocked: blocking.length > 0,
    reviewDigest: `${merged.length} total finding(s), ${blocking.length} blocking.`,
  };
}

function validationPassed(validation: any): boolean {
  return Boolean(validation) && validation.validationBlocked !== true && validation.dockerBuildPassed !== false && validation.smokePassed !== false;
}

export default smithers((ctx) => {
  const closeoutPlanPath = ctx.input.closeoutPlanPath ?? DEFAULT_CLOSEOUT_PLAN;
  const sourcePlanPaths = ctx.input.sourcePlanPaths ?? DEFAULT_SOURCE_PLANS;
  const blockingSeverities = ctx.input.blockingSeverities ?? ["P0", "P1", "P2"];
  const validationProfile = ctx.input.validationProfile ?? "headless-linux-docker-bounded";
  const scope = ctx.outputMaybe("scope", { nodeId: "establish-scope" });
  const reviews = ctx.outputs.review ?? [];
  const latestReview = reviews.at(-1);
  const normalizedReviews = ctx.outputs.normalizedReview ?? [];
  const latestNormalized = normalizedReviews.at(-1);
  const currentNormalized = latestReview ? normalizeReview(latestReview, blockingSeverities) : latestNormalized;
  const validations = ctx.outputs.validation ?? [];
  const latestValidation = validations.at(-1);
  const shouldFix = currentNormalized?.completionBlocked === true && currentNormalized.malformedReview !== true;
  const done = currentNormalized !== undefined && currentNormalized.completionBlocked === false && validationPassed(latestValidation);

  return (
    <Workflow name="headless-closeout-grinder">
      <Sequence>
        <Task id="establish-scope" output={outputs.scope} agent={agents.smartTool}>
          <EstablishScopePrompt
            closeoutPlanPath={closeoutPlanPath}
            sourcePlanPaths={sourcePlanPaths}
            ceCodeReviewSkill={CE_CODE_REVIEW_SKILL}
            operatorPrompt={ctx.input.prompt}
          />
        </Task>

        {scope ? (
          <Task id="ce-review" output={outputs.review} agent={agents.smart} timeoutMs={1_800_000} heartbeatTimeoutMs={600_000}>
            <CeReviewPrompt
              scope={scope}
              closeoutPlanPath={closeoutPlanPath}
              ceCodeReviewSkill={CE_CODE_REVIEW_SKILL}
              operatorPrompt={ctx.input.prompt}
            />
          </Task>
        ) : null}

        {latestReview ? (
          <Task id="normalize-review" output={outputs.normalizedReview}>
            {currentNormalized}
          </Task>
        ) : null}

        {currentNormalized ? (
          <Loop id="grind-loop" until={done} maxIterations={ctx.input.maxIterations ?? 3} onMaxReached="return-last">
            <Sequence>
              <Branch
                if={shouldFix}
                then={
                  <Sequence>
                    <Task id="fix-plan" output={outputs.fixPlan} agent={agents.smart}>
                      <FixPlanPrompt
                        scope={scope}
                        normalizedReview={currentNormalized}
                        sourcePlanPaths={sourcePlanPaths}
                        operatorPrompt={ctx.input.prompt}
                      />
                    </Task>

                    <Task id="apply-fixes" output={outputs.fixResult} agent={agents.smartTool} timeoutMs={1_800_000} heartbeatTimeoutMs={600_000}>
                      <ApplyFixesPrompt
                        scope={scope}
                        normalizedReview={currentNormalized}
                        fixPlan={ctx.outputMaybe("fixPlan", { nodeId: "fix-plan" })}
                        operatorPrompt={ctx.input.prompt}
                      />
                    </Task>
                  </Sequence>
                }
                else={null}
              />

              <Task id="bounded-validation" output={outputs.validation} agent={agents.smartTool} timeoutMs={1_800_000} heartbeatTimeoutMs={600_000}>
                <ValidationPrompt
                  validationProfile={validationProfile}
                  scope={scope}
                  latestFix={ctx.outputMaybe("fixResult", { nodeId: "apply-fixes" })}
                  operatorPrompt={ctx.input.prompt}
                />
              </Task>

              <Task id="ce-review-followup" output={outputs.review} agent={agents.smart} timeoutMs={1_800_000} heartbeatTimeoutMs={600_000}>
                <CeReviewPrompt
                  scope={scope}
                  closeoutPlanPath={closeoutPlanPath}
                  ceCodeReviewSkill={CE_CODE_REVIEW_SKILL}
                  operatorPrompt={ctx.input.prompt}
                />
              </Task>

              <Task id="normalize-review-followup" output={outputs.normalizedReview}>
                {ctx.outputs.review?.at(-1) ? normalizeReview(ctx.outputs.review.at(-1), blockingSeverities) : currentNormalized}
              </Task>
            </Sequence>
          </Loop>
        ) : null}

        {currentNormalized ? (
          <Task id="landing-packet" output={outputs.landingPacket} agent={agents.smart}>
            <LandingPacketPrompt
              scope={scope}
              normalizedReviews={
                normalizedReviews.at(-1) === currentNormalized ? normalizedReviews : [...normalizedReviews, currentNormalized]
              }
              currentNormalized={currentNormalized}
              validations={validations}
              latestValidation={latestValidation}
              done={done}
              operatorPrompt={ctx.input.prompt}
            />
          </Task>
        ) : null}
      </Sequence>
    </Workflow>
  );
});
