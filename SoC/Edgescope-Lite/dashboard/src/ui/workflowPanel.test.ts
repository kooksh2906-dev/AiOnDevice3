import { describe, expect, it } from "vitest";

import type { FirmwareState, WorkflowSnapshot } from "../app/captureModel";
import { workflowInstruction } from "./workflowPanel";

function workflow(state: FirmwareState): WorkflowSnapshot {
  return {
    transactionId: "A0000001",
    demo: "rising",
    attempt: 1,
    state,
    code: "TEST",
  };
}

describe("workflow instruction", () => {
  it("does not tell the user to trigger while merely READY", () => {
    expect(workflowInstruction(workflow("READY"))).toContain(
      "아직 Switch를 바꾸지 마세요",
    );
    expect(workflowInstruction(workflow("READY"))).not.toContain(
      "0x00에서 0x01로 변경",
    );
  });

  it("shows the physical trigger action only in GO", () => {
    expect(workflowInstruction(workflow("GO"))).toContain(
      "0x00에서 0x01로 변경",
    );
  });
});
