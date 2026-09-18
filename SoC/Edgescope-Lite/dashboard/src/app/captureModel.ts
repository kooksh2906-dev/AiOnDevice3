export const CAPTURE_DEPTH = 1024;
export const TRIGGER_INDEX = 512;
export const DATA_CHUNK_LENGTH = 64;
export const DATA_FRAME_COUNT = CAPTURE_DEPTH / DATA_CHUNK_LENGTH;

export type DemoKey = "rising" | "falling" | "pattern";
export type TriggerMode = "RISING" | "FALLING" | "PATTERN";

export interface DemoSpec {
  readonly key: DemoKey;
  readonly protocolId: number;
  readonly title: string;
  readonly subtitle: string;
  readonly mode: TriggerMode;
  readonly divider: 1 | 8;
  readonly channel: number | null;
  readonly patternValue: number;
  readonly patternMask: number;
  readonly initialValue: number;
  readonly triggerValue: number;
  readonly goInstruction: string;
}

export const DEMO_SPECS: Readonly<Record<DemoKey, DemoSpec>> = {
  rising: {
    key: "rising",
    protocolId: 1,
    title: "Device Start",
    subtitle: "Rising edge · CH0",
    mode: "RISING",
    divider: 1,
    channel: 0,
    patternValue: 0,
    patternMask: 0,
    initialValue: 0x00,
    triggerValue: 0x01,
    goInstruction: "SW[7:0]을 0x00에서 0x01로 변경하고 유지하세요.",
  },
  falling: {
    key: "falling",
    protocolId: 2,
    title: "Enable Loss",
    subtitle: "Falling edge · CH1",
    mode: "FALLING",
    divider: 8,
    channel: 1,
    patternValue: 0,
    patternMask: 0,
    initialValue: 0x02,
    triggerValue: 0x00,
    goInstruction: "SW[7:0]을 0x02에서 0x00으로 변경하고 유지하세요.",
  },
  pattern: {
    key: "pattern",
    protocolId: 3,
    title: "Fault Entry",
    subtitle: "Masked pattern · A0/F0",
    mode: "PATTERN",
    divider: 1,
    channel: null,
    patternValue: 0xa0,
    patternMask: 0xf0,
    initialValue: 0x25,
    triggerValue: 0xa5,
    goInstruction: "SW[7:0]을 0x25에서 0xA5로 변경하고 유지하세요.",
  },
};

export const FIRMWARE_STATES = [
  "WAIT_START",
  "PRE_READY",
  "READY",
  "GO",
  "DONE",
  "WAIT_REPLAY_BEFORE",
  "WAIT_REPLAY_AFTER",
  "WAIT_FREEZE",
  "TX",
  "TIMEOUT",
  "RETRY",
  "PASS",
  "FAIL",
] as const;

export type FirmwareState = (typeof FIRMWARE_STATES)[number];

export interface WorkflowSnapshot {
  readonly transactionId: string;
  readonly demo: DemoKey;
  readonly attempt: number;
  readonly state: FirmwareState;
  readonly code: string;
}

export interface CheckResult {
  readonly pass: boolean;
  readonly detail: string;
}

export interface CaptureValidation {
  readonly frameCrc: CheckResult;
  readonly sampleFnv: CheckResult;
  readonly length: CheckResult;
  readonly sequence: CheckResult;
  readonly freeze: CheckResult;
}

export interface CaptureMetadata {
  readonly transactionId: string;
  readonly attempt: number;
  readonly demo: DemoKey;
  readonly mode: TriggerMode;
  readonly divider: 1 | 8;
  readonly channel: number | null;
  readonly patternValue: number;
  readonly patternMask: number;
  readonly status: number;
  readonly depth: number;
  readonly triggerIndex: number;
  readonly startAddress: number;
  readonly triggerAddress: number;
  readonly writeAddress: number;
  readonly triggerCountBefore: number;
  readonly triggerCountAfter: number;
  readonly passBits: number | null;
}

export interface ValidatedCapture {
  readonly metadata: CaptureMetadata;
  readonly samples: Uint8Array;
  readonly validation: CaptureValidation;
  readonly receivedAt: number;
}

export interface CaptureDisplayCheck {
  readonly accepted: boolean;
  readonly reasons: readonly string[];
}

export function formatHex(value: number, width = 2): string {
  return value.toString(16).toUpperCase().padStart(width, "0");
}

export function samplePeriodNs(divider: 1 | 8): number {
  return divider * 10;
}

export function fnv1a32(bytes: Uint8Array): number {
  let hash = 0x811c9dc5;

  for (const byte of bytes) {
    hash ^= byte;
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }

  return hash >>> 0;
}

export function createMockSamples(demo: DemoKey): Uint8Array {
  const samples = new Uint8Array(CAPTURE_DEPTH);
  const spec = DEMO_SPECS[demo];
  samples.fill(spec.initialValue, 0, TRIGGER_INDEX);
  samples.fill(spec.triggerValue, TRIGGER_INDEX);

  return samples;
}

export function createMockCapture(
  demo: DemoKey,
  transactionId: string,
  attempt = 1,
  receivedAt = Date.now(),
): ValidatedCapture {
  const spec = DEMO_SPECS[demo];
  const samples = createMockSamples(demo);
  const sampleFnv = fnv1a32(samples);
  const transactionSeed = [...transactionId].reduce(
    (sum, character) => sum + character.charCodeAt(0),
    0,
  );
  const startAddress =
    (0x120 + spec.protocolId * 0x4d + transactionSeed) & 0x3ff;
  const triggerAddress = (startAddress + TRIGGER_INDEX) & 0x3ff;
  const writeAddress = (startAddress + CAPTURE_DEPTH - 1) & 0x3ff;
  const triggerCountBefore = Math.max(0, spec.protocolId - 1);

  return {
    metadata: {
      transactionId,
      attempt,
      demo,
      mode: spec.mode,
      divider: spec.divider,
      channel: spec.channel,
      patternValue: spec.patternValue,
      patternMask: spec.patternMask,
      status: 0x0e,
      depth: CAPTURE_DEPTH,
      triggerIndex: TRIGGER_INDEX,
      startAddress,
      triggerAddress,
      writeAddress,
      triggerCountBefore,
      triggerCountAfter: triggerCountBefore + 1,
      passBits: null,
    },
    samples,
    validation: {
      frameCrc: {
        pass: true,
        detail: `${DATA_FRAME_COUNT + 2}/${DATA_FRAME_COUNT + 2} frames`,
      },
      sampleFnv: {
        pass: true,
        detail: `0x${formatHex(sampleFnv, 8)}`,
      },
      length: {
        pass: true,
        detail: `${CAPTURE_DEPTH} samples`,
      },
      sequence: {
        pass: true,
        detail: "00—0F continuous",
      },
      freeze: {
        pass: true,
        detail: "BRAM stable",
      },
    },
    receivedAt,
  };
}

function validateTriggerBoundary(capture: ValidatedCapture): string | null {
  const before = capture.samples[TRIGGER_INDEX - 1];
  const trigger = capture.samples[TRIGGER_INDEX];

  if (before === undefined || trigger === undefined) {
    return "Trigger 경계 Sample이 없습니다.";
  }

  const demo = capture.metadata.demo;
  if (demo === "rising" && ((before & 0x01) !== 0 || (trigger & 0x01) === 0)) {
    return "Rising CH0 Trigger 경계가 일치하지 않습니다.";
  }

  if (demo === "falling" && ((before & 0x02) === 0 || (trigger & 0x02) !== 0)) {
    return "Falling CH1 Trigger 경계가 일치하지 않습니다.";
  }

  if (demo === "pattern") {
    const mask = capture.metadata.patternMask;
    const value = capture.metadata.patternValue & mask;
    if ((before & mask) === value || (trigger & mask) !== value) {
      return "Masked Pattern Trigger 경계가 일치하지 않습니다.";
    }
  }

  return null;
}

export function validateCaptureForDisplay(
  capture: ValidatedCapture,
): CaptureDisplayCheck {
  const reasons: string[] = [];
  const { metadata, samples, validation } = capture;
  const demoSpec = DEMO_SPECS[metadata.demo];

  if (metadata.depth !== CAPTURE_DEPTH) {
    reasons.push(`Capture depth ${metadata.depth}은 ${CAPTURE_DEPTH}이 아닙니다.`);
  }
  if (metadata.triggerIndex !== TRIGGER_INDEX) {
    reasons.push(
      `Trigger index ${metadata.triggerIndex}은 ${TRIGGER_INDEX}가 아닙니다.`,
    );
  }
  if (samples.length !== metadata.depth) {
    reasons.push(
      `Sample length ${samples.length}이 META depth ${metadata.depth}와 다릅니다.`,
    );
  }
  if (metadata.mode !== demoSpec.mode) {
    reasons.push(
      `Demo mode ${metadata.mode}가 기대값 ${demoSpec.mode}와 다릅니다.`,
    );
  }
  if (metadata.divider !== demoSpec.divider) {
    reasons.push(
      `Demo divider ${metadata.divider}가 기대값 ${demoSpec.divider}와 다릅니다.`,
    );
  }
  if (metadata.channel !== demoSpec.channel) {
    reasons.push(
      `Trigger channel ${String(metadata.channel)}이 기대값 ` +
        `${String(demoSpec.channel)}과 다릅니다.`,
    );
  }
  if (
    metadata.patternValue !== demoSpec.patternValue ||
    metadata.patternMask !== demoSpec.patternMask
  ) {
    reasons.push("Pattern value/mask가 선택한 Demo 정의와 다릅니다.");
  }
  if (
    ((metadata.triggerAddress - metadata.startAddress) & 0x3ff) !==
    metadata.triggerIndex
  ) {
    reasons.push("START/TRIGGER circular address 관계가 올바르지 않습니다.");
  }
  if (((metadata.writeAddress + 1) & 0x3ff) !== metadata.startAddress) {
    reasons.push("WRITE/START circular address 관계가 올바르지 않습니다.");
  }

  const validationEntries: ReadonlyArray<[string, CheckResult]> = [
    ["Frame CRC", validation.frameCrc],
    ["Capture FNV", validation.sampleFnv],
    ["Length", validation.length],
    ["Sequence", validation.sequence],
    ["BRAM Freeze", validation.freeze],
  ];

  for (const [name, result] of validationEntries) {
    if (!result.pass) {
      reasons.push(`${name} 검증에 실패했습니다: ${result.detail}`);
    }
  }

  if (samples.length === CAPTURE_DEPTH) {
    const triggerReason = validateTriggerBoundary(capture);
    if (triggerReason !== null) {
      reasons.push(triggerReason);
    }
  }

  return { accepted: reasons.length === 0, reasons };
}
