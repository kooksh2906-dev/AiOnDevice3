import { describe, expect, it } from "vitest";

import {
  TRIGGER_INDEX,
  createMockCapture,
  createMockSamples,
} from "../app/captureModel";
import {
  buildBusRuns,
  buildDigitalRuns,
  getViewWindow,
  sampleBoundaryX,
  sampleTimeNs,
} from "./waveformCanvas";

describe("waveform geometry", () => {
  it("uses exact half-open full and trigger windows", () => {
    expect(getViewWindow(1024, 512, "full")).toEqual({
      start: 0,
      endExclusive: 1024,
    });
    expect(getViewWindow(1024, 512, "trigger")).toEqual({
      start: 448,
      endExclusive: 576,
    });
  });

  it("places trigger boundary at the exact plot center", () => {
    const window = getViewWindow(1024, TRIGGER_INDEX, "trigger");
    expect(sampleBoundaryX(512, window, 64, 960)).toBeCloseTo(544, 8);
  });

  it("aligns every demo transition to boundary 512", () => {
    const window = { start: 448, endExclusive: 576 };
    const cases = [
      { demo: "rising" as const, channel: 0 },
      { demo: "falling" as const, channel: 1 },
    ];

    for (const { demo, channel } of cases) {
      const runs = buildDigitalRuns(createMockSamples(demo), channel, window);
      expect(runs.some((run) => run.endExclusive === TRIGGER_INDEX)).toBe(true);
      expect(runs.some((run) => run.start === TRIGGER_INDEX)).toBe(true);
    }

    const patternRuns = buildBusRuns(createMockSamples("pattern"), window);
    expect(
      patternRuns.some((run) => run.endExclusive === TRIGGER_INDEX),
    ).toBe(true);
    expect(patternRuns.some((run) => run.start === TRIGGER_INDEX)).toBe(true);
  });

  it("converts divider sample positions to trigger-relative time", () => {
    expect(sampleTimeNs(511, 512, 10)).toBe(-10);
    expect(sampleTimeNs(512, 512, 10)).toBe(0);
    expect(sampleTimeNs(1023, 512, 80)).toBe(40_880);
  });

  it("keeps the model trigger boundary valid in full view", () => {
    const capture = createMockCapture("pattern", "A0000001");
    const full = getViewWindow(
      capture.metadata.depth,
      capture.metadata.triggerIndex,
      "full",
    );
    expect(sampleBoundaryX(512, full, 64, 960)).toBe(544);
  });
});
