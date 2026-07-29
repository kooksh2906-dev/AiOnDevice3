import type { WorkflowSnapshot } from "./captureModel";
import type { ConnectionState } from "../transport/transport";

export interface ControlPolicy {
  readonly canConnect: boolean;
  readonly canDisconnect: boolean;
  readonly canSync: boolean;
  readonly canStart: boolean;
  readonly canFinishFreeze: boolean;
  readonly canConfigureMock: boolean;
}

export function getControlPolicy(
  connection: ConnectionState,
  workflow: WorkflowSnapshot | null,
): ControlPolicy {
  const connected = connection === "connected";
  const transitioning =
    connection === "connecting" || connection === "disconnecting";
  const state = workflow?.state ?? null;

  return {
    canConnect: !connected && !transitioning && connection !== "error",
    canDisconnect: connected || connection === "error",
    canSync:
      connected && (state === "WAIT_START" || state === "WAIT_FREEZE"),
    canStart: connected && state === "WAIT_START",
    canFinishFreeze: connected && state === "WAIT_FREEZE",
    canConfigureMock: !connected || state === "WAIT_START",
  };
}
