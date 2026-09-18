import {
  DEMO_SPECS,
  formatHex,
  type FirmwareState,
  type ValidatedCapture,
  type WorkflowSnapshot,
} from "../app/captureModel";

function stateTone(state: FirmwareState): "idle" | "busy" | "go" | "pass" | "error" {
  if (state === "GO") {
    return "go";
  }
  if (state === "PASS") {
    return "pass";
  }
  if (state === "TIMEOUT" || state === "RETRY" || state === "FAIL") {
    return "error";
  }
  if (
    state === "PRE_READY" ||
    state === "READY" ||
    state === "DONE" ||
    state === "WAIT_REPLAY_BEFORE" ||
    state === "WAIT_REPLAY_AFTER" ||
    state === "WAIT_FREEZE" ||
    state === "TX"
  ) {
    return "busy";
  }
  return "idle";
}

export function workflowInstruction(workflow: WorkflowSnapshot): string {
  const spec = DEMO_SPECS[workflow.demo];
  switch (workflow.state) {
    case "WAIT_START":
      return (
        `초기 SW를 0x${formatHex(spec.initialValue)}로 맞춘 뒤 ` +
        "Capture 시작을 누르세요."
      );
    case "PRE_READY":
      return "Pre-trigger 512 Sample을 채우는 중입니다.";
    case "READY":
      return "Trigger baseline이 안정화됐습니다. 아직 Switch를 바꾸지 마세요.";
    case "GO":
      return spec.goInstruction;
    case "DONE":
      return "Capture 완료. BRAM Freeze와 One-shot 검사를 시작합니다.";
    case "WAIT_REPLAY_BEFORE":
      return `One-shot 이전 값 0x${formatHex(spec.initialValue)}를 확인합니다.`;
    case "WAIT_REPLAY_AFTER":
      return `One-shot 조건 값 0x${formatHex(spec.triggerValue)}를 확인합니다.`;
    case "WAIT_FREEZE":
      return "SW[7:0]=0x3C를 유지하고 Freeze 완료를 누르세요.";
    case "TX":
      return "Compact Capture를 전송하고 검증하는 중입니다.";
    case "TIMEOUT":
      return "10초 안에 Trigger가 없어 현재 Attempt를 폐기했습니다.";
    case "RETRY":
      return "Abort/Clear/Disable 완료. 초기값을 복원하세요.";
    case "PASS":
      return "Capture와 안정성 검증이 모두 통과했습니다.";
    case "FAIL":
      return "현재 Transaction을 표시하지 않고 이전 검증 파형을 유지합니다.";
  }
}

export class WorkflowPanel {
  public constructor(
    private readonly root: HTMLElement,
    private readonly transactionBadge: HTMLElement,
  ) {
    this.render(null, null, false);
  }

  public render(
    workflow: WorkflowSnapshot | null,
    lastGoodCapture: ValidatedCapture | null,
    showingPreviousCapture: boolean,
  ): void {
    this.root.replaceChildren();
    this.transactionBadge.textContent =
      workflow === null ? "TXN —" : `TXN ${workflow.transactionId}`;

    if (workflow === null) {
      const empty = document.createElement("div");
      empty.className = "empty-card";
      empty.textContent =
        "연결 후 Firmware STATE를 기다립니다. Trigger 조작은 GO에서만 안내합니다.";
      this.root.append(empty);
      return;
    }

    const content = document.createElement("div");
    content.className = "workflow-content";
    const stateBlock = document.createElement("div");
    stateBlock.className = "workflow-state";
    const tone = stateTone(workflow.state);

    const orb = document.createElement("span");
    orb.className =
      tone === "idle" ? "workflow-orb" : `workflow-orb workflow-orb--${tone}`;
    orb.setAttribute("aria-hidden", "true");

    const copy = document.createElement("div");
    copy.className = "workflow-copy";
    const state = document.createElement("strong");
    state.textContent = workflow.state;
    const detail = document.createElement("p");
    detail.textContent =
      `${DEMO_SPECS[workflow.demo].subtitle} · Attempt ${workflow.attempt} · ` +
      workflow.code;
    copy.append(state, detail);
    stateBlock.append(orb, copy);

    const instruction = document.createElement("div");
    instruction.className =
      workflow.state === "GO"
        ? "instruction-box instruction-box--action"
        : "instruction-box";
    instruction.textContent = workflowInstruction(workflow);

    content.append(stateBlock, instruction);

    if (lastGoodCapture !== null) {
      const verified = document.createElement("div");
      verified.className = showingPreviousCapture
        ? "verified-capture verified-capture--stale"
        : "verified-capture";
      verified.textContent = showingPreviousCapture
        ? `이전 검증 TXN ${lastGoodCapture.metadata.transactionId} 표시 유지`
        : `검증 파형 TXN ${lastGoodCapture.metadata.transactionId} 표시 중`;
      content.append(verified);
    }

    this.root.append(content);
  }
}
