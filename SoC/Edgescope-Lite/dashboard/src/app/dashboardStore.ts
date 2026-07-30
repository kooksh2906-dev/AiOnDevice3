import {
  validateCaptureForDisplay,
  type ValidatedCapture,
  type WorkflowSnapshot,
} from "./captureModel";
import type {
  ConnectionState,
  DashboardEvent,
  TransportStatus,
} from "../transport/transport";

export interface DashboardState {
  readonly transport: TransportStatus;
  readonly workflow: WorkflowSnapshot | null;
  readonly lastGoodCapture: ValidatedCapture | null;
  readonly alert: string | null;
  readonly showingPreviousCapture: boolean;
}

const INITIAL_STATE: DashboardState = {
  transport: {
    state: "disconnected",
    message: "연결 안 됨",
  },
  workflow: null,
  lastGoodCapture: null,
  alert: null,
  showingPreviousCapture: false,
};

export type DashboardStateListener = (state: DashboardState) => void;

function snapshotCapture(capture: ValidatedCapture): ValidatedCapture {
  return {
    metadata: { ...capture.metadata },
    samples: capture.samples.slice(),
    validation: {
      frameCrc: { ...capture.validation.frameCrc },
      sampleFnv: { ...capture.validation.sampleFnv },
      length: { ...capture.validation.length },
      sequence: { ...capture.validation.sequence },
      freeze: { ...capture.validation.freeze },
    },
    receivedAt: capture.receivedAt,
  };
}

export class DashboardStore {
  private stateValue: DashboardState = INITIAL_STATE;
  private readonly listeners = new Set<DashboardStateListener>();

  public get state(): DashboardState {
    return this.stateValue;
  }

  public subscribe(listener: DashboardStateListener): () => void {
    this.listeners.add(listener);
    listener(this.stateValue);
    return () => {
      this.listeners.delete(listener);
    };
  }

  public clearAlert(): void {
    if (this.stateValue.alert === null) {
      return;
    }
    this.commit({ ...this.stateValue, alert: null });
  }

  public invalidateWorkflow(): void {
    this.commit({
      ...this.stateValue,
      workflow: null,
      showingPreviousCapture: this.stateValue.lastGoodCapture !== null,
    });
  }

  public resetSession(connectionState: ConnectionState = "disconnected"): void {
    this.commit({
      ...INITIAL_STATE,
      transport: {
        state: connectionState,
        message: connectionState === "disconnected" ? "연결 안 됨" : connectionState,
      },
      lastGoodCapture: this.stateValue.lastGoodCapture,
      showingPreviousCapture: this.stateValue.lastGoodCapture !== null,
    });
  }

  public accept(event: DashboardEvent): boolean {
    switch (event.type) {
      case "raw":
      case "bytes":
        return true;
      case "transport":
        const invalidatesWorkflow =
          event.status.state !== "connected";
        this.commit({
          ...this.stateValue,
          transport: event.status,
          workflow: invalidatesWorkflow ? null : this.stateValue.workflow,
          alert:
            event.status.state === "error"
              ? event.status.message
              : this.stateValue.alert,
          showingPreviousCapture:
            invalidatesWorkflow &&
            this.stateValue.lastGoodCapture !== null
              ? true
              : this.stateValue.showingPreviousCapture,
        });
        return true;
      case "workflow": {
        const failed =
          event.workflow.state === "TIMEOUT" || event.workflow.state === "FAIL";
        const differentTransaction =
          this.stateValue.lastGoodCapture !== null &&
          event.workflow.transactionId !==
            this.stateValue.lastGoodCapture.metadata.transactionId;
        this.commit({
          ...this.stateValue,
          workflow: event.workflow,
          alert:
            event.workflow.state === "TIMEOUT"
              ? `TXN ${event.workflow.transactionId}: 10초 Trigger Timeout. ` +
                "현재 Attempt를 폐기하고 이전 검증 파형을 유지합니다."
              : event.workflow.state === "FAIL" &&
                  this.stateValue.alert === null
                ? `TXN ${event.workflow.transactionId}: Firmware 검증 실패. ` +
                  "이전 검증 파형을 유지합니다."
                : this.stateValue.alert,
          showingPreviousCapture:
            (failed || differentTransaction) &&
            this.stateValue.lastGoodCapture !== null
              ? true
              : this.stateValue.showingPreviousCapture,
        });
        return true;
      }
      case "capture": {
        const check = validateCaptureForDisplay(event.capture);
        if (!check.accepted) {
          this.commit({
            ...this.stateValue,
            alert: check.reasons.join(" "),
            showingPreviousCapture: this.stateValue.lastGoodCapture !== null,
          });
          return false;
        }

        this.commit({
          ...this.stateValue,
          lastGoodCapture: snapshotCapture(event.capture),
          alert: null,
          showingPreviousCapture: false,
        });
        return true;
      }
      case "capture-rejected":
        this.commit({
          ...this.stateValue,
          alert: event.message,
          showingPreviousCapture: this.stateValue.lastGoodCapture !== null,
        });
        return false;
      case "error":
        this.commit({
          ...this.stateValue,
          alert: event.message,
          showingPreviousCapture: this.stateValue.lastGoodCapture !== null,
        });
        return false;
    }
  }

  private commit(next: DashboardState): void {
    this.stateValue = next;
    for (const listener of this.listeners) {
      listener(next);
    }
  }
}
