import { describe, expect, test } from "bun:test";
import { REQUIRED_VALIDATION_LANES, normalizeReview, validationPassed } from "../lib/headlessCloseoutGate";

const blocking = ["P0", "P1", "P2"];
const passingLanes = Object.fromEntries(
  REQUIRED_VALIDATION_LANES.map((lane) => [
    lane,
    {
      status: lane === "contribution_readiness" ? "pending_main_chat_staging" : "pass",
      evidence: [`${lane} evidence`],
    },
  ]),
);

function passingValidation(overrides = {}) {
  return {
    validationBlocked: false,
    dockerBuildPassed: true,
    smokePassed: true,
    validationEvidence: ["build ok", "smoke ok"],
    validationLanes: passingLanes,
    ...overrides,
  };
}

describe("headless closeout gate", () => {
  test("validation fails closed for sparse or blocked evidence", () => {
    expect(validationPassed(null)).toBe(false);
    expect(validationPassed({ validationBlocked: false, dockerBuildPassed: true, smokePassed: true })).toBe(false);
    expect(validationPassed({ validationBlocked: false, dockerBuildPassed: null, smokePassed: true, validationEvidence: ["smoke ok"] })).toBe(false);
    expect(validationPassed({ validationBlocked: false, dockerBuildPassed: true, smokePassed: null, validationEvidence: ["build ok"] })).toBe(false);
    expect(validationPassed({ validationBlocked: true, dockerBuildPassed: true, smokePassed: true, validationEvidence: ["all ok"] })).toBe(false);
    expect(validationPassed({ validationBlocked: false, dockerBuildPassed: true, smokePassed: true, validationEvidence: [] })).toBe(false);
    expect(validationPassed(passingValidation())).toBe(true);
  });

  test("validation fails when any required lane is omitted or lacks evidence", () => {
    for (const lane of REQUIRED_VALIDATION_LANES) {
      const validation = passingValidation({
        validationLanes: {
          ...passingLanes,
          [lane]: undefined,
        },
      });
      expect(validationPassed(validation), lane).toBe(false);

      const sparse = passingValidation({
        validationLanes: {
          ...passingLanes,
          [lane]: { status: "pass", evidence: [] },
        },
      });
      expect(validationPassed(sparse), `${lane} evidence`).toBe(false);
    }
  });

  test("blocking severities block even when actionableFindings is omitted or actionable is false", () => {
    const normalized = normalizeReview({
      reviewResult: {
        status: "complete",
        verdict: "Ready with fixes",
        findings: [
          { "#": 7, severity: "P1", title: "timeout can mutate stale state", actionable: false, evidence: "race evidence" },
          { id: "nit-1", severity: "nit", title: "wording" },
        ],
      },
    }, blocking);

    expect(normalized.completionBlocked).toBe(true);
    expect(normalized.blockingFindings).toHaveLength(1);
    expect(normalized.blockingFindings[0].id).toBe("ce-7");
    expect(normalized.blockingFindings[0].actionable).toBe(true);
    expect(normalized.nonBlockingFindings[0].id).toBe("nit-1");
  });

  test("malformed CE review output becomes a P1 workflow blocker", () => {
    for (const review of [null, { parseable: false, malformedReason: "json parse failed" }, { status: "failed", summary: "agent failed" }]) {
      const normalized = normalizeReview(review, blocking);
      expect(normalized.malformedReview).toBe(true);
      expect(normalized.completionBlocked).toBe(true);
      expect(normalized.blockingFindings[0].severity).toBe("P1");
      expect(normalized.blockingFindings[0].id).toBe("malformed-review-json");
    }
  });

  test("degraded or sparse CE review output becomes a P1 workflow blocker", () => {
    for (const review of [
      { reviewResult: { status: "degraded", verdict: "Not ready" }, findings: [], actionableFindings: [] },
      { reviewResult: { status: "complete" }, findings: [], actionableFindings: [] },
      { reviewResult: { status: "complete", verdict: "Looks good" }, findings: [], actionableFindings: [] },
      { findings: [], actionableFindings: [] },
    ]) {
      const normalized = normalizeReview(review, blocking);
      expect(normalized.malformedReview).toBe(true);
      expect(normalized.completionBlocked).toBe(true);
      expect(normalized.blockingFindings[0].severity).toBe("P1");
    }
  });

  test("stable ids and array evidence are preserved", () => {
    const normalized = normalizeReview({
      reviewResult: {
        status: "complete",
        artifact_path: "/tmp/review.json",
        findings: [
          { "#": "12", severity: "P2", title: "schema drift", evidence: [{ file: "HeadlessToolSchemas.swift", line: 42, text: "oneOf only" }] },
          { id: "explicit", severity: "P3", title: "minor", evidence: ["first", "second"] },
          { severity: "P2", title: "fallback", file: "Service.swift", line: 9 },
        ],
      },
    }, blocking);

    expect(normalized.allFindings.map((finding) => finding.id)).toEqual([
      "ce-12",
      "explicit",
      "Service.swift:9:fallback",
    ]);
    expect(normalized.allFindings[0].evidence).toContain("HeadlessToolSchemas.swift: 42: oneOf only");
    expect(normalized.allFindings[1].evidence).toBe("first\nsecond");
  });

  test("complete review with finding evidence is trusted", () => {
    const normalized = normalizeReview({
      reviewResult: {
        status: "complete",
      },
      findings: [
        { "#": 3, severity: "P3", title: "minor", evidence: "reviewed path and behavior" },
      ],
    }, blocking);

    expect(normalized.malformedReview).toBe(false);
    expect(normalized.completionBlocked).toBe(false);
    expect(normalized.allFindings[0].id).toBe("ce-3");
  });
});
