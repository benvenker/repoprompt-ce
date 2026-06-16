export type CloseoutSeverity = "P0" | "P1" | "P2" | "P3" | "nit";

export type NormalizedFinding = {
  id: string;
  severity: CloseoutSeverity;
  title: string;
  file: string | null;
  line: number | null;
  actionable: boolean;
  source: string;
  evidence: string | null;
  recommendation: string | null;
};

export type NormalizedReview = {
  summary: string;
  allFindings: NormalizedFinding[];
  blockingFindings: NormalizedFinding[];
  nonBlockingFindings: NormalizedFinding[];
  malformedReview: boolean;
  completionBlocked: boolean;
  reviewDigest: string;
};

export type ValidationGateInput = {
  validationBlocked?: boolean | null;
  dockerBuildPassed?: boolean | null;
  smokePassed?: boolean | null;
  validationEvidence?: unknown;
  validationLanes?: Record<string, ValidationLaneInput> | null;
};

const SEVERITIES: CloseoutSeverity[] = ["P0", "P1", "P2", "P3", "nit"];
const TRUSTED_REVIEW_STATUSES = new Set(["complete", "completed"]);
export const REQUIRED_VALIDATION_LANES = [
  "smithers_helper_tests",
  "smithers_static_validation",
  "docker_headless_build",
  "fake_agent_lifecycle_smoke",
  "mcp_smoke",
  "source_layout_guardrails",
  "diff_check",
  "contribution_readiness",
] as const;

type ValidationLaneInput = {
  status?: unknown;
  evidence?: unknown;
  allowedHostGap?: unknown;
};

function asArray(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

function normalizeSeverity(value: unknown): CloseoutSeverity {
  return SEVERITIES.includes(value as CloseoutSeverity) ? (value as CloseoutSeverity) : "P3";
}

function nonEmptyString(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : null;
}

function stableFindingID(value: any, index: number, file: string | null, line: number | null, title: string): string {
  const explicitID = nonEmptyString(value?.id);
  if (explicitID) { return explicitID; }

  const ceNumber = value?.["#"];
  if (typeof ceNumber === "number" && Number.isFinite(ceNumber)) {
    return `ce-${Math.floor(ceNumber)}`;
  }
  const ceString = nonEmptyString(ceNumber);
  if (ceString) {
    return ceString.startsWith("ce-") ? ceString : `ce-${ceString}`;
  }

  const fallback = [file, line, title].filter((part) => part !== null && part !== "").join(":");
  return fallback || `finding-${index + 1}`;
}

function evidenceText(value: unknown): string | null {
  const direct = nonEmptyString(value);
  if (direct) { return direct; }

  if (Array.isArray(value)) {
    const rendered = value
      .map((item) => {
        if (typeof item === "string") { return item.trim(); }
        if (item && typeof item === "object") {
          const object = item as Record<string, unknown>;
          const parts = [
            nonEmptyString(object.file),
            typeof object.line === "number" && Number.isFinite(object.line) ? String(Math.floor(object.line)) : null,
            nonEmptyString(object.text) ?? nonEmptyString(object.quote) ?? nonEmptyString(object.summary),
          ].filter(Boolean);
          return parts.join(": ");
        }
        return null;
      })
      .filter((item): item is string => Boolean(item && item.length > 0));
    return rendered.length > 0 ? rendered.join("\n") : null;
  }

  return null;
}

export function normalizeFinding(
  value: any,
  index: number,
  actionableDefault: boolean,
  blockingSeverities: string[],
): NormalizedFinding {
  const line = typeof value?.line === "number" && Number.isFinite(value.line) && value.line > 0 ? Math.floor(value.line) : null;
  const file = nonEmptyString(value?.file);
  const title = nonEmptyString(value?.title) ?? nonEmptyString(value?.issue) ?? `Review finding ${index + 1}`;
  const severity = normalizeSeverity(value?.severity);
  const isBlockingSeverity = blockingSeverities.includes(severity);

  return {
    id: stableFindingID(value, index, file, line, title),
    severity,
    title,
    file,
    line,
    actionable: isBlockingSeverity || (typeof value?.actionable === "boolean" ? value.actionable : actionableDefault),
    source: nonEmptyString(value?.source) ?? "ce-code-review",
    evidence: evidenceText(value?.evidence),
    recommendation: nonEmptyString(value?.recommendation) ?? nonEmptyString(value?.suggested_fix),
  };
}

export function normalizeReview(review: any, blockingSeverities: string[]): NormalizedReview {
  const reviewBlocker = reviewTrustBlocker(review);
  if (reviewBlocker) {
    return blockedReview(reviewBlocker);
  }

  const source = review.reviewResult ?? review;
  const actionable = asArray(source?.actionable_findings ?? source?.actionableFindings ?? review.actionableFindings).map((finding, index) =>
    normalizeFinding(finding, index, true, blockingSeverities),
  );
  const all = asArray(source?.findings ?? review.findings).map((finding, index) => normalizeFinding(finding, index, false, blockingSeverities));
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

export function validationPassed(validation: ValidationGateInput | null | undefined): boolean {
  const evidence = asArray(validation?.validationEvidence).filter((item) => typeof item === "string" && item.trim().length > 0);
  return Boolean(
    validation &&
    validation.validationBlocked === false &&
    validation.dockerBuildPassed === true &&
    validation.smokePassed === true &&
    evidence.length > 0 &&
    REQUIRED_VALIDATION_LANES.every((lane) => validationLanePassed(validation.validationLanes?.[lane], lane)),
  );
}

function reviewTrustBlocker(review: any): NormalizedFinding | null {
  if (!review || review.parseable === false) {
    return workflowBlocker(
      "ce-code-review result was missing or malformed",
      nonEmptyString(review?.malformedReason) ?? nonEmptyString(review?.summary) ?? "No parseable CE review result was produced.",
    );
  }

  const source = review.reviewResult ?? review;
  const status = nonEmptyString(source?.status ?? review.status)?.toLowerCase() ?? null;
  if (!status || !TRUSTED_REVIEW_STATUSES.has(status)) {
    return workflowBlocker(
      "ce-code-review result was not explicitly trustworthy",
      `Review status was ${status ?? "missing"}; expected complete/completed with evidence.`,
    );
  }

  if (!reviewHasEvidence(source, review)) {
    return workflowBlocker(
      "ce-code-review result was too sparse to trust",
      "Review status was complete, but compact review evidence was missing.",
    );
  }

  return null;
}

function workflowBlocker(title: string, evidence: string): NormalizedFinding {
  return {
    id: "malformed-review-json",
    severity: "P1",
    title,
    file: null,
    line: null,
    actionable: true,
    source: "workflow",
    evidence,
    recommendation: "Rerun or repair the CE review step before declaring closeout complete.",
  };
}

function blockedReview(blocker: NormalizedFinding): NormalizedReview {
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

function reviewHasEvidence(source: any, review: any): boolean {
  return Boolean(
    nonEmptyString(source?.artifact_path) ||
    nonEmptyString(source?.coverage_summary) ||
    asArray(source?.requirement_summary).length > 0 ||
    asArray(source?.residual_risks).length > 0 ||
    asArray(source?.testing_gaps).length > 0 ||
    asArray(source?.notes).length > 0 ||
    asArray(source?.findings ?? review?.findings).some((finding: any) => evidenceText(finding?.evidence)) ||
    asArray(source?.actionableFindings ?? source?.actionable_findings ?? review?.actionableFindings).some((finding: any) => evidenceText(finding?.evidence)),
  );
}

function validationLanePassed(lane: ValidationLaneInput | undefined, laneName: string): boolean {
  const status = nonEmptyString(lane?.status)?.toLowerCase() ?? null;
  const evidence = asArray(lane?.evidence).filter((item) => typeof item === "string" && item.trim().length > 0);
  if (!status || evidence.length === 0) { return false; }
  if (status === "pass") { return true; }
  if (status === "allowed_host_gap" && lane?.allowedHostGap === true) { return true; }
  return laneName === "contribution_readiness" && status === "pending_main_chat_staging";
}
