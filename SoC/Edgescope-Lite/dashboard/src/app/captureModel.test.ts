import { describe, expect, it } from "vitest";

import {
  CAPTURE_DEPTH,
  TRIGGER_INDEX,
  createMockCapture,
  fnv1a32,
  validateCaptureForDisplay,
  type DemoKey,
  type ValidatedCapture,
} from "./captureModel";

describe("capture model", () => {
  it("matches the frozen FNV-1a reference vector", () => {
    const samples = Uint8Array.from(
      { length: CAPTURE_DEPTH },
      (_, index) => index & 0xff,
    );

    expect(fnv1a32(samples)).toBe(0x840389c5);
  });

  it.each<
    readonly [
      DemoKey,
      number,
      number,
      number,
      (before: number, trigger: number) => boolean,
    ]
  >([
    [
      "rising",
      0x00,
      0x01,
      0x5b608fc5,
      (before, trigger) => (before & 1) === 0 && (trigger & 1) === 1,
    ],
    [
      "falling",
      0x02,
      0x00,
      0xc9c105c5,
      (before, trigger) => (before & 2) === 2 && (trigger & 2) === 0,
    ],
    [
      "pattern",
      0x25,
      0xa5,
      0xa36d71c5,
      (before, trigger) =>
        (before & 0xf0) !== 0xa0 && (trigger & 0xf0) === 0xa0,
    ],
  ])(
    "creates a display-safe %s mock capture",
    (demo, expectedBefore, expectedTrigger, expectedFnv, boundaryMatches) => {
    const capture = createMockCapture(demo, "A0000001");
    const before = capture.samples[TRIGGER_INDEX - 1] ?? 0;
    const trigger = capture.samples[TRIGGER_INDEX] ?? 0;

    expect(capture.samples).toHaveLength(CAPTURE_DEPTH);
    expect(before).toBe(expectedBefore);
    expect(trigger).toBe(expectedTrigger);
    expect(boundaryMatches(before, trigger)).toBe(true);
    expect(fnv1a32(capture.samples)).toBe(expectedFnv);
    expect(validateCaptureForDisplay(capture)).toEqual({
      accepted: true,
      reasons: [],
    });
    },
  );

  it("rejects an incomplete capture without mutating the original", () => {
    const valid = createMockCapture("rising", "A0000001");
    const incomplete: ValidatedCapture = {
      ...valid,
      samples: valid.samples.slice(0, CAPTURE_DEPTH - 1),
    };

    const result = validateCaptureForDisplay(incomplete);

    expect(result.accepted).toBe(false);
    expect(result.reasons.join(" ")).toContain("Sample length");
    expect(valid.samples).toHaveLength(CAPTURE_DEPTH);
  });

  it("rejects a named integrity failure", () => {
    const valid = createMockCapture("pattern", "A0000002");
    const corrupt: ValidatedCapture = {
      ...valid,
      validation: {
        ...valid.validation,
        frameCrc: { pass: false, detail: "DATA seq 07" },
      },
    };

    const result = validateCaptureForDisplay(corrupt);

    expect(result.accepted).toBe(false);
    expect(result.reasons).toContain(
      "Frame CRC 검증에 실패했습니다: DATA seq 07",
    );
  });

  it("rejects demo metadata that would create a misleading label", () => {
    const valid = createMockCapture("falling", "A0000003");
    const mismatched: ValidatedCapture = {
      ...valid,
      metadata: {
        ...valid.metadata,
        divider: 1,
        channel: 0,
      },
    };

    const result = validateCaptureForDisplay(mismatched);

    expect(result.accepted).toBe(false);
    expect(result.reasons.join(" ")).toContain("Demo divider");
    expect(result.reasons.join(" ")).toContain("Trigger channel");
  });
});
