// smithers-source: local
// smithers-metadata-version: 1
// smithers-display-name: Headless Closeout Grinder
// smithers-description: Iterate CE code review, scoped fixes, and bounded headless validation until no P0/P1/P2 findings remain.
// smithers-tags: review,implementation,headless
/** @jsxImportSource smithers-orchestrator */
import { createSmithers } from "smithers-orchestrator";
import { z } from "zod/v4";
import { providers } from "../agents";
import { normalizeReview, validationPassed } from "../lib/headlessCloseoutGate";
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
const CE_CODE_REVIEW_SKILL = "compound-engineering:ce-code-review";
const CODEX_55_HIGH_AGENTS = [providers.codex55High];

const severitySchema = z.enum(["P0", "P1", "P2", "P3", "nit"]);
const findingEvidenceSchema = z.union([
  z.string(),
  z.array(z.unknown()),
  z.record(z.string(), z.unknown()),
]);

const findingSchema = z.looseObject({
  id: z.string(),
  severity: severitySchema,
  title: z.string(),
  file: z.string().nullable().default(null),
  line: z.number().int().positive().nullable().default(null),
  actionable: z.boolean().default(false),
  source: z.string().default("ce-code-review"),
  evidence: findingEvidenceSchema.nullable().default(null),
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
  validationLanes: z.record(
    z.string(),
    z.looseObject({
      status: z.string(),
      evidence: z.array(z.string()).default([]),
      allowedHostGap: z.boolean().default(false),
    }),
  ).default({}),
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
        <Task id="establish-scope" output={outputs.scope} agent={CODEX_55_HIGH_AGENTS}>
          <EstablishScopePrompt
            closeoutPlanPath={closeoutPlanPath}
            sourcePlanPaths={sourcePlanPaths}
            ceCodeReviewSkill={CE_CODE_REVIEW_SKILL}
            operatorPrompt={ctx.input.prompt}
          />
        </Task>

        {scope ? (
          <Task id="ce-review" output={outputs.review} agent={CODEX_55_HIGH_AGENTS} timeoutMs={1_800_000} heartbeatTimeoutMs={600_000}>
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
                    <Task id="fix-plan" output={outputs.fixPlan} agent={CODEX_55_HIGH_AGENTS}>
                      <FixPlanPrompt
                        scope={scope}
                        normalizedReview={currentNormalized}
                        sourcePlanPaths={sourcePlanPaths}
                        operatorPrompt={ctx.input.prompt}
                      />
                    </Task>

                    <Task id="apply-fixes" output={outputs.fixResult} agent={CODEX_55_HIGH_AGENTS} timeoutMs={1_800_000} heartbeatTimeoutMs={600_000}>
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

              <Task id="bounded-validation" output={outputs.validation} agent={CODEX_55_HIGH_AGENTS} timeoutMs={1_800_000} heartbeatTimeoutMs={600_000}>
                <ValidationPrompt
                  validationProfile={validationProfile}
                  scope={scope}
                  latestFix={ctx.outputMaybe("fixResult", { nodeId: "apply-fixes" })}
                  operatorPrompt={ctx.input.prompt}
                />
              </Task>

              <Task id="ce-review-followup" output={outputs.review} agent={CODEX_55_HIGH_AGENTS} timeoutMs={1_800_000} heartbeatTimeoutMs={600_000}>
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
          <Task id="landing-packet" output={outputs.landingPacket} agent={CODEX_55_HIGH_AGENTS}>
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
