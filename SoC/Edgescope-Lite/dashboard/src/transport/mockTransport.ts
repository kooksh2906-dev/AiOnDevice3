import {
  createMockCapture,
  type DemoKey,
  type FirmwareState,
  type WorkflowSnapshot,
} from "../app/captureModel";
import {
  EventTransport,
  type ConfigurableMockTransport,
  type ConnectionState,
  type ControlCommand,
  type MockScenario,
} from "./transport";

export interface MockTransportOptions {
  readonly delayMs?: number;
  readonly now?: () => number;
}

const DEFAULT_TRANSACTION = "A0000000";

export class MockTransport
  extends EventTransport
  implements ConfigurableMockTransport
{
  public readonly kind = "mock" as const;

  private stateValue: ConnectionState = "disconnected";
  private demoValue: DemoKey = "rising";
  private scenarioValue: MockScenario = "normal";
  private transactionCounter = 0;
  private attempt = 1;
  private workflowValue: WorkflowSnapshot = {
    transactionId: DEFAULT_TRANSACTION,
    demo: this.demoValue,
    attempt: this.attempt,
    state: "WAIT_START",
    code: "MOCK_READY",
  };
  private hasConnectedOnce = false;
  private operationInFlight = false;
  private sessionGeneration = 0;
  private readonly delayMs: number;
  private readonly now: () => number;

  public constructor(options: MockTransportOptions = {}) {
    super();
    this.delayMs = options.delayMs ?? 125;
    this.now = options.now ?? Date.now;
  }

  public get connectionState(): ConnectionState {
    return this.stateValue;
  }

  public setDemo(demo: DemoKey): void {
    if (this.operationInFlight || this.workflowValue.state !== "WAIT_START") {
      return;
    }

    this.demoValue = demo;
    this.attempt = 1;
    this.workflowValue = {
      ...this.workflowValue,
      demo,
      attempt: this.attempt,
      code: "MOCK_DEMO_SELECTED",
    };

    if (this.stateValue === "connected") {
      this.emit({ type: "workflow", workflow: this.workflowValue });
      this.emitRaw("system", `[mock] demo selected: ${demo}`);
    }
  }

  public setScenario(scenario: MockScenario): void {
    if (this.operationInFlight || this.workflowValue.state !== "WAIT_START") {
      return;
    }

    this.scenarioValue = scenario;
    if (this.stateValue === "connected") {
      this.emitRaw("system", `[mock] scenario selected: ${scenario}`);
    }
  }

  public async connect(): Promise<void> {
    if (this.stateValue === "connected" || this.stateValue === "connecting") {
      return;
    }

    this.setConnection("connecting", "Mock fixture 준비 중");
    this.sessionGeneration += 1;
    await this.pause();
    this.setConnection("connected", "Mock fixture 연결됨");
    this.emitRaw("system", "[mock] semantic fixture session opened");

    if (this.hasConnectedOnce) {
      this.emitRaw("tx", "?");
      this.emitRaw("system", "[mock] reconnect resync requested");
    }

    this.emit({
      type: "workflow",
      workflow: {
        ...this.workflowValue,
        demo: this.demoValue,
      },
    });
    this.hasConnectedOnce = true;
  }

  public async disconnect(): Promise<void> {
    if (this.stateValue === "disconnected") {
      return;
    }

    this.setConnection("disconnecting", "Mock fixture 연결 해제 중");
    this.sessionGeneration += 1;
    await this.pause();
    const interrupted = this.workflowValue.state !== "WAIT_START";
    if (interrupted) {
      this.attempt += 1;
    }
    this.workflowValue = {
      ...this.workflowValue,
      attempt: this.attempt,
      state: "WAIT_START",
      code: interrupted ? "MOCK_SESSION_RESET" : "MOCK_READY",
    };
    this.operationInFlight = false;
    this.setConnection("disconnected", "연결 안 됨");
    this.emitRaw("system", "[mock] session closed; last verified capture retained");
  }

  public async sendCommand(command: ControlCommand): Promise<void> {
    this.assertConnected();
    this.emitRaw("tx", command);

    if (command === "?") {
      this.emitRaw("system", "[mock] HELLO + current state replay");
      this.emit({ type: "workflow", workflow: this.workflowValue });
      return;
    }

    if (this.operationInFlight) {
      this.rejectCommand(command, "다른 Mock 작업이 진행 중입니다.");
    }

    if (command === "s") {
      if (this.workflowValue.state !== "WAIT_START") {
        this.rejectCommand(
          command,
          `s는 WAIT_START에서만 허용됩니다. 현재 ${this.workflowValue.state}`,
        );
      }
      await this.runStartSequence();
      return;
    }

    if (this.workflowValue.state !== "WAIT_FREEZE") {
      this.rejectCommand(
        command,
        `f는 WAIT_FREEZE에서만 허용됩니다. 현재 ${this.workflowValue.state}`,
      );
    }
    await this.runFreezeSequence();
  }

  private async runStartSequence(): Promise<void> {
    this.operationInFlight = true;
    const generation = this.sessionGeneration;
    this.transactionCounter += 1;
    const transactionId = `A${this.transactionCounter
      .toString(16)
      .toUpperCase()
      .padStart(7, "0")}`;

    try {
      await this.progress("PRE_READY", "PREFILL_512", transactionId, generation);
      await this.progress(
        "READY",
        "BASELINE_STABLE",
        transactionId,
        generation,
      );
      await this.progress(
        "GO",
        "TRIGGER_WINDOW_OPEN",
        transactionId,
        generation,
      );

      if (this.scenarioValue === "timeout") {
        await this.progress(
          "TIMEOUT",
          "NO_TRIGGER_10S",
          transactionId,
          generation,
        );
        await this.progress(
          "RETRY",
          "ABORT_CLEAR_DISABLE",
          transactionId,
          generation,
        );
        this.attempt += 1;
        await this.progress(
          "WAIT_START",
          "RESTORE_INITIAL_STATE",
          transactionId,
          generation,
        );
        return;
      }

      await this.progress("DONE", "CAPTURE_FROZEN", transactionId, generation);
      await this.progress(
        "WAIT_REPLAY_BEFORE",
        "ONE_SHOT_BEFORE",
        transactionId,
        generation,
      );
      await this.progress(
        "WAIT_REPLAY_AFTER",
        "ONE_SHOT_AFTER",
        transactionId,
        generation,
      );
      await this.progress(
        "WAIT_FREEZE",
        "HOLD_3C_AND_SEND_F",
        transactionId,
        generation,
      );
    } finally {
      this.operationInFlight = false;
    }
  }

  private async runFreezeSequence(): Promise<void> {
    this.operationInFlight = true;
    const generation = this.sessionGeneration;
    const transactionId = this.workflowValue.transactionId;

    try {
      await this.progress(
        "TX",
        "MOCK_CAPTURE_EXPORT",
        transactionId,
        generation,
      );

      if (this.scenarioValue === "corrupt") {
        const message =
          `TXN ${transactionId} Mock Frame CRC 오류: ` +
          "이전 검증 파형을 유지합니다.";
        this.emit({
          type: "capture-rejected",
          message,
          transactionId,
        });
        await this.progress("FAIL", "FRAME_CRC", transactionId, generation);
        this.attempt += 1;
        await this.progress(
          "WAIT_START",
          "NEW_ATTEMPT_REQUIRED",
          transactionId,
          generation,
        );
        return;
      }

      const capture = createMockCapture(
        this.demoValue,
        transactionId,
        this.attempt,
        this.now(),
      );
      this.emit({ type: "capture", capture });
      await this.progress(
        "PASS",
        "ALL_CHECKS_PASS",
        transactionId,
        generation,
      );
      this.attempt = 1;
      await this.progress(
        "WAIT_START",
        "NEXT_CAPTURE_READY",
        transactionId,
        generation,
      );
    } finally {
      this.operationInFlight = false;
    }
  }

  private async progress(
    state: FirmwareState,
    code: string,
    transactionId: string,
    generation: number,
  ): Promise<void> {
    await this.pause();
    if (
      generation !== this.sessionGeneration ||
      this.stateValue !== "connected"
    ) {
      throw new Error("Mock session changed during playback.");
    }
    this.workflowValue = {
      transactionId,
      demo: this.demoValue,
      attempt: this.attempt,
      state,
      code,
    };
    this.emit({ type: "workflow", workflow: this.workflowValue });
    this.emitRaw(
      "system",
      `[mock] ${transactionId} ${this.demoValue} A${this.attempt} ${state} ${code}`,
    );
  }

  private setConnection(state: ConnectionState, message: string): void {
    this.stateValue = state;
    this.emit({
      type: "transport",
      status: { state, message },
    });
  }

  private emitRaw(
    direction: "rx" | "tx" | "system",
    text: string,
  ): void {
    this.emit({
      type: "raw",
      direction,
      text,
      timestamp: this.now(),
    });
  }

  private assertConnected(): void {
    if (this.stateValue !== "connected") {
      const message = "Mock fixture가 연결되지 않았습니다.";
      this.emit({ type: "error", message, recoverable: true });
      throw new Error(message);
    }
  }

  private rejectCommand(command: ControlCommand, reason: string): never {
    const message = `명령 '${command}' 거부: ${reason}`;
    this.emit({ type: "error", message, recoverable: true });
    throw new Error(message);
  }

  private async pause(): Promise<void> {
    if (this.delayMs <= 0) {
      await Promise.resolve();
      return;
    }
    await new Promise<void>((resolve) => {
      globalThis.setTimeout(resolve, this.delayMs);
    });
  }
}
