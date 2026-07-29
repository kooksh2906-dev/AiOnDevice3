import { describe, expect, it } from "vitest";

import type { FirmwareState, WorkflowSnapshot } from "./captureModel";
import { getControlPolicy } from "./controlPolicy";

function workflow(state: FirmwareState): WorkflowSnapshot {
  return {
    transactionId: "A0000001",
    demo: "rising",
    attempt: 1,
    state,
    code: "TEST",
  };
}

describe("control policy", () => {
  it("allows s only in WAIT_START", () => {
    expect(getControlPolicy("connected", workflow("WAIT_START")).canStart).toBe(
      true,
    );
    expect(getControlPolicy("connected", workflow("READY")).canStart).toBe(
      false,
    );
  });

  it("allows f only in WAIT_FREEZE", () => {
    expect(
      getControlPolicy("connected", workflow("WAIT_FREEZE")).canFinishFreeze,
    ).toBe(true);
    expect(
      getControlPolicy("connected", workflow("DONE")).canFinishFreeze,
    ).toBe(false);
  });

  it("allows manual sync only in UART wait states", () => {
    expect(getControlPolicy("connected", workflow("WAIT_START")).canSync).toBe(
      true,
    );
    expect(getControlPolicy("connected", workflow("WAIT_FREEZE")).canSync).toBe(
      true,
    );
    expect(getControlPolicy("connected", workflow("READY")).canSync).toBe(
      false,
    );
    expect(getControlPolicy("connected", workflow("TX")).canSync).toBe(false);
  });

  it("gates every command while disconnected", () => {
    const policy = getControlPolicy("disconnected", workflow("WAIT_START"));
    expect(policy.canStart).toBe(false);
    expect(policy.canFinishFreeze).toBe(false);
    expect(policy.canSync).toBe(false);
  });
});
