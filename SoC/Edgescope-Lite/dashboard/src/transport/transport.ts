import type {
  DemoKey,
  ValidatedCapture,
  WorkflowSnapshot,
} from "../app/captureModel";

export type ControlCommand = "s" | "f" | "?";
export type TransportKind = "mock" | "serial";
export type ConnectionState =
  | "disconnected"
  | "connecting"
  | "connected"
  | "disconnecting"
  | "unsupported"
  | "error";

export type MockScenario = "normal" | "timeout" | "corrupt";

export interface TransportStatus {
  readonly state: ConnectionState;
  readonly message: string;
}

export type DashboardEvent =
  | {
      readonly type: "transport";
      readonly status: TransportStatus;
    }
  | {
      readonly type: "bytes";
      readonly data: Uint8Array;
    }
  | {
      readonly type: "raw";
      readonly direction: "rx" | "tx" | "system";
      readonly text: string;
      readonly timestamp: number;
    }
  | {
      readonly type: "workflow";
      readonly workflow: WorkflowSnapshot;
    }
  | {
      readonly type: "capture";
      readonly capture: ValidatedCapture;
    }
  | {
      readonly type: "capture-rejected";
      readonly message: string;
      readonly transactionId: string | null;
    }
  | {
      readonly type: "error";
      readonly message: string;
      readonly recoverable: boolean;
    };

export type DashboardEventListener = (event: DashboardEvent) => void;

export interface DashboardTransport {
  readonly kind: TransportKind;
  readonly connectionState: ConnectionState;
  connect(): Promise<void>;
  disconnect(): Promise<void>;
  sendCommand(command: ControlCommand): Promise<void>;
  subscribe(listener: DashboardEventListener): () => void;
}

export interface ConfigurableMockTransport extends DashboardTransport {
  readonly kind: "mock";
  setDemo(demo: DemoKey): void;
  setScenario(scenario: MockScenario): void;
}

export abstract class EventTransport implements DashboardTransport {
  public abstract readonly kind: TransportKind;
  public abstract get connectionState(): ConnectionState;

  private readonly listeners = new Set<DashboardEventListener>();

  public abstract connect(): Promise<void>;
  public abstract disconnect(): Promise<void>;
  public abstract sendCommand(command: ControlCommand): Promise<void>;

  public subscribe(listener: DashboardEventListener): () => void {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  }

  protected emit(event: DashboardEvent): void {
    for (const listener of this.listeners) {
      listener(event);
    }
  }
}
