import { describe, expect, it } from "vitest";

import { createMockCapture } from "./captureModel";
import { getControlPolicy } from "./controlPolicy";
import { DashboardStore } from "./dashboardStore";

describe("DashboardStore", () => {
  it("atomically swaps only validated captures", () => {
    const store = new DashboardStore();
    const first = createMockCapture("rising", "A0000001");
    const second = createMockCapture("falling", "A0000002");

    expect(store.accept({ type: "capture", capture: first })).toBe(true);
    expect(store.state.lastGoodCapture?.metadata.transactionId).toBe(
      "A0000001",
    );
    expect(store.state.lastGoodCapture?.samples).not.toBe(first.samples);
    expect(store.accept({ type: "capture", capture: second })).toBe(true);
    expect(store.state.lastGoodCapture?.metadata.transactionId).toBe(
      "A0000002",
    );
  });

  it("retains the last good capture after a rejected transaction", () => {
    const store = new DashboardStore();
    const capture = createMockCapture("rising", "A0000001");
    store.accept({ type: "capture", capture });
    const storedCapture = store.state.lastGoodCapture;

    expect(
      store.accept({
        type: "capture-rejected",
        transactionId: "A0000002",
        message: "CRC 오류",
      }),
    ).toBe(false);
    expect(store.state.lastGoodCapture).toBe(storedCapture);
    expect(store.state.showingPreviousCapture).toBe(true);
    expect(store.state.alert).toBe("CRC 오류");
  });

  it("retains the waveform through timeout and disconnect", () => {
    const store = new DashboardStore();
    const capture = createMockCapture("pattern", "A0000001");
    store.accept({ type: "capture", capture });
    const storedCapture = store.state.lastGoodCapture;
    store.accept({
      type: "workflow",
      workflow: {
        transactionId: "A0000002",
        demo: "pattern",
        attempt: 2,
        state: "TIMEOUT",
        code: "NO_TRIGGER_10S",
      },
    });
    store.accept({
      type: "transport",
      status: { state: "disconnected", message: "USB disconnected" },
    });

    expect(store.state.lastGoodCapture).toBe(storedCapture);
    expect(store.state.showingPreviousCapture).toBe(true);
    expect(store.state.alert).toContain("10초 Trigger Timeout");
  });

  it("invalidates stale firmware state until a new session reports STATE", () => {
    const store = new DashboardStore();
    store.accept({
      type: "workflow",
      workflow: {
        transactionId: "A0000001",
        demo: "rising",
        attempt: 1,
        state: "WAIT_FREEZE",
        code: "HOLD_3C",
      },
    });
    store.accept({
      type: "transport",
      status: { state: "disconnecting", message: "closing" },
    });
    store.accept({
      type: "transport",
      status: { state: "connected", message: "reopened" },
    });

    expect(store.state.workflow).toBeNull();
    expect(
      getControlPolicy(store.state.transport.state, store.state.workflow)
        .canFinishFreeze,
    ).toBe(false);
  });

  it("invalidates workflow immediately for manual resync", () => {
    const store = new DashboardStore();
    store.accept({
      type: "workflow",
      workflow: {
        transactionId: "A0000001",
        demo: "rising",
        attempt: 1,
        state: "WAIT_START",
        code: "READY",
      },
    });

    store.invalidateWorkflow();

    expect(store.state.workflow).toBeNull();
  });

  it("rejects malformed semantic data while retaining object identity", () => {
    const store = new DashboardStore();
    const good = createMockCapture("falling", "A0000001");
    store.accept({ type: "capture", capture: good });
    const storedCapture = store.state.lastGoodCapture;
    const malformed = {
      ...createMockCapture("falling", "A0000002"),
      metadata: {
        ...createMockCapture("falling", "A0000002").metadata,
        triggerIndex: 511,
      },
    };

    expect(store.accept({ type: "capture", capture: malformed })).toBe(false);
    expect(store.state.lastGoodCapture).toBe(storedCapture);
  });
});
