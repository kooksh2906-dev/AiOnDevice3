import type { DashboardEvent } from "../transport/transport";

export type ProtocolResetReason =
  | "disconnect"
  | "new-session"
  | "manual-resync";

/**
 * Role C owns the implementation under src/protocol/.
 *
 * Role B only consumes semantic events from this boundary. In particular, this
 * interface deliberately says nothing about line splitting, frame fields, CRC,
 * FNV, chunk order, or END/RESULT assembly while UART Protocol v1 is unfrozen.
 */
export interface ProtocolBridge {
  ingest(chunk: Uint8Array): readonly DashboardEvent[];
  reset(reason: ProtocolResetReason): readonly DashboardEvent[];
}

/**
 * Safe Stage-2 default: Live bytes remain visible in Raw Log, but cannot mutate
 * the waveform until Role C supplies a validated decoder/assembler.
 */
export class PendingProtocolBridge implements ProtocolBridge {
  public ingest(_chunk: Uint8Array): readonly DashboardEvent[] {
    return [];
  }

  public reset(_reason: ProtocolResetReason): readonly DashboardEvent[] {
    return [];
  }
}
