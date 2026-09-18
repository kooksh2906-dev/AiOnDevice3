import {
  CAPTURE_DEPTH,
  DEMO_SPECS,
  TRIGGER_INDEX,
  formatHex,
  samplePeriodNs,
  type ValidatedCapture,
} from "../app/captureModel";

export type WaveformViewMode = "full" | "trigger";

export interface ViewWindow {
  readonly start: number;
  readonly endExclusive: number;
}

export interface DigitalRun {
  readonly start: number;
  readonly endExclusive: number;
  readonly level: 0 | 1;
}

export interface BusRun {
  readonly start: number;
  readonly endExclusive: number;
  readonly value: number;
}

export interface WaveformCanvasOptions {
  readonly onViewportChange?: (window: ViewWindow) => void;
}

const TRIGGER_ZOOM_SPAN = 128;
const CHANNEL_COLORS = [
  "#69e4ee",
  "#66b4ff",
  "#88dbb4",
  "#c3a8ff",
  "#ffcb77",
  "#ee8fb2",
  "#8fd3ff",
  "#b3e06f",
] as const;

export function getViewWindow(
  depth: number,
  triggerIndex: number,
  mode: WaveformViewMode,
): ViewWindow {
  if (mode === "full" || depth <= TRIGGER_ZOOM_SPAN) {
    return { start: 0, endExclusive: depth };
  }

  const half = TRIGGER_ZOOM_SPAN / 2;
  const unclampedStart = triggerIndex - half;
  const start = Math.max(0, Math.min(unclampedStart, depth - TRIGGER_ZOOM_SPAN));
  return { start, endExclusive: start + TRIGGER_ZOOM_SPAN };
}

export function sampleBoundaryX(
  sampleIndex: number,
  window: ViewWindow,
  left: number,
  plotWidth: number,
): number {
  const span = window.endExclusive - window.start;
  if (span <= 0) {
    return left;
  }
  return left + ((sampleIndex - window.start) / span) * plotWidth;
}

export function buildDigitalRuns(
  samples: Uint8Array,
  channel: number,
  window: ViewWindow,
): readonly DigitalRun[] {
  if (
    channel < 0 ||
    channel > 7 ||
    window.start < 0 ||
    window.endExclusive > samples.length ||
    window.start >= window.endExclusive
  ) {
    return [];
  }

  const runs: DigitalRun[] = [];
  let runStart = window.start;
  let level = ((samples[runStart] ?? 0) >>> channel) & 0x01;

  for (
    let index = window.start + 1;
    index < window.endExclusive;
    index += 1
  ) {
    const nextLevel = ((samples[index] ?? 0) >>> channel) & 0x01;
    if (nextLevel !== level) {
      runs.push({
        start: runStart,
        endExclusive: index,
        level: level as 0 | 1,
      });
      runStart = index;
      level = nextLevel;
    }
  }

  runs.push({
    start: runStart,
    endExclusive: window.endExclusive,
    level: level as 0 | 1,
  });
  return runs;
}

export function buildBusRuns(
  samples: Uint8Array,
  window: ViewWindow,
): readonly BusRun[] {
  if (
    window.start < 0 ||
    window.endExclusive > samples.length ||
    window.start >= window.endExclusive
  ) {
    return [];
  }

  const runs: BusRun[] = [];
  let runStart = window.start;
  let value = samples[runStart] ?? 0;

  for (
    let index = window.start + 1;
    index < window.endExclusive;
    index += 1
  ) {
    const nextValue = samples[index] ?? 0;
    if (nextValue !== value) {
      runs.push({ start: runStart, endExclusive: index, value });
      runStart = index;
      value = nextValue;
    }
  }

  runs.push({ start: runStart, endExclusive: window.endExclusive, value });
  return runs;
}

export function sampleTimeNs(
  sampleIndex: number,
  triggerIndex: number,
  samplePeriodNs: number,
): number {
  return (sampleIndex - triggerIndex) * samplePeriodNs;
}

function formatTime(nanoseconds: number): string {
  if (nanoseconds === 0) {
    return "0";
  }
  const absolute = Math.abs(nanoseconds);
  if (absolute >= 1000) {
    const microseconds = nanoseconds / 1000;
    return `${Number.isInteger(microseconds) ? microseconds : microseconds.toFixed(2)} µs`;
  }
  return `${nanoseconds} ns`;
}

export class WaveformCanvas {
  private readonly canvas: HTMLCanvasElement;
  private readonly context: CanvasRenderingContext2D;
  private readonly resizeObserver: ResizeObserver;
  private readonly onViewportChange: (window: ViewWindow) => void;
  private capture: ValidatedCapture | null = null;
  private mode: WaveformViewMode = "full";

  public constructor(
    canvas: HTMLCanvasElement,
    options: WaveformCanvasOptions = {},
  ) {
    const context = canvas.getContext("2d");
    if (context === null) {
      throw new Error("Canvas 2D context를 만들 수 없습니다.");
    }

    this.canvas = canvas;
    this.context = context;
    this.onViewportChange = options.onViewportChange ?? (() => undefined);
    this.resizeObserver = new ResizeObserver(() => {
      this.render();
    });
    this.resizeObserver.observe(canvas);
  }

  public setCapture(capture: ValidatedCapture | null): void {
    this.capture = capture;
    this.render();
  }

  public setViewMode(mode: WaveformViewMode): void {
    if (this.mode === mode) {
      return;
    }
    this.mode = mode;
    this.render();
  }

  public get viewMode(): WaveformViewMode {
    return this.mode;
  }

  public get viewWindow(): ViewWindow {
    const depth = this.capture?.metadata.depth ?? CAPTURE_DEPTH;
    const triggerIndex = this.capture?.metadata.triggerIndex ?? TRIGGER_INDEX;
    return getViewWindow(depth, triggerIndex, this.mode);
  }

  public destroy(): void {
    this.resizeObserver.disconnect();
  }

  public render(): void {
    const cssWidth = Math.max(1, this.canvas.clientWidth);
    const cssHeight = Math.max(1, this.canvas.clientHeight);
    const pixelRatio = Math.max(1, globalThis.devicePixelRatio || 1);
    const backingWidth = Math.round(cssWidth * pixelRatio);
    const backingHeight = Math.round(cssHeight * pixelRatio);

    if (
      this.canvas.width !== backingWidth ||
      this.canvas.height !== backingHeight
    ) {
      this.canvas.width = backingWidth;
      this.canvas.height = backingHeight;
    }

    const context = this.context;
    context.setTransform(pixelRatio, 0, 0, pixelRatio, 0, 0);
    context.clearRect(0, 0, cssWidth, cssHeight);

    if (this.capture === null) {
      this.drawEmptyGrid(cssWidth, cssHeight);
      this.onViewportChange(this.viewWindow);
      return;
    }

    this.drawCapture(this.capture, cssWidth, cssHeight);
  }

  private drawCapture(
    capture: ValidatedCapture,
    width: number,
    height: number,
  ): void {
    const context = this.context;
    const window = this.viewWindow;
    const left = width < 560 ? 50 : 64;
    const right = 18;
    const top = 31;
    const bottom = 55;
    const busHeight = 31;
    const plotWidth = Math.max(1, width - left - right);
    const channelAreaHeight = Math.max(120, height - top - bottom - busHeight);
    const channelHeight = channelAreaHeight / 8;
    const plotBottom = top + channelAreaHeight;

    context.save();
    this.drawGrid(
      capture,
      window,
      left,
      top,
      plotWidth,
      channelAreaHeight + busHeight,
    );

    for (let channel = 0; channel < 8; channel += 1) {
      const trackTop = top + channel * channelHeight;
      const trackCenter = trackTop + channelHeight / 2;
      const amplitude = Math.min(8, channelHeight * 0.28);

      context.fillStyle =
        channel % 2 === 0 ? "rgba(118, 155, 190, 0.025)" : "transparent";
      context.fillRect(left, trackTop, plotWidth, channelHeight);

      context.fillStyle = "#7990a8";
      context.font = '600 9px "SFMono-Regular", Consolas, monospace';
      context.textAlign = "right";
      context.textBaseline = "middle";
      context.fillText(`CH${channel}`, left - 12, trackCenter);

      const runs = buildDigitalRuns(capture.samples, channel, window);
      context.beginPath();
      context.strokeStyle = CHANNEL_COLORS[channel] ?? "#69e4ee";
      context.lineWidth = 1.25;
      context.lineJoin = "miter";

      runs.forEach((run, index) => {
        const startX = sampleBoundaryX(run.start, window, left, plotWidth);
        const endX = sampleBoundaryX(
          run.endExclusive,
          window,
          left,
          plotWidth,
        );
        const y =
          run.level === 1 ? trackCenter - amplitude : trackCenter + amplitude;

        if (index === 0) {
          context.moveTo(startX, y);
        }
        context.lineTo(endX, y);

        const nextRun = runs[index + 1];
        if (nextRun !== undefined) {
          const nextY =
            nextRun.level === 1
              ? trackCenter - amplitude
              : trackCenter + amplitude;
          context.lineTo(endX, nextY);
        }
      });
      context.stroke();
    }

    this.drawBus(capture, window, left, plotBottom, plotWidth, busHeight);
    this.drawTriggerMarker(
      capture,
      window,
      left,
      top,
      plotWidth,
      channelAreaHeight + busHeight,
    );
    this.drawTimeAxis(capture, window, left, plotBottom + busHeight, plotWidth);
    context.restore();

    const spec = DEMO_SPECS[capture.metadata.demo];
    this.canvas.setAttribute(
      "aria-label",
      `${spec.subtitle}, 8채널 ${capture.samples.length} Sample, ` +
        `Divider ${capture.metadata.divider}, Trigger index ` +
        `${capture.metadata.triggerIndex}, CRC와 FNV 검증 통과`,
    );
    this.onViewportChange(window);
  }

  private drawGrid(
    capture: ValidatedCapture,
    window: ViewWindow,
    left: number,
    top: number,
    width: number,
    height: number,
  ): void {
    const context = this.context;
    const divisions = 8;

    context.strokeStyle = "rgba(131, 164, 197, 0.11)";
    context.lineWidth = 1;
    context.setLineDash([2, 5]);

    for (let division = 0; division <= divisions; division += 1) {
      const sample =
        window.start +
        ((window.endExclusive - window.start) * division) / divisions;
      const x = sampleBoundaryX(sample, window, left, width);
      context.beginPath();
      context.moveTo(Math.round(x) + 0.5, top);
      context.lineTo(Math.round(x) + 0.5, top + height);
      context.stroke();
    }
    context.setLineDash([]);

    context.fillStyle = "#657c94";
    context.font = '500 8px "SFMono-Regular", Consolas, monospace';
    context.textBaseline = "top";
    context.textAlign = "left";
    context.fillText(
      `${capture.metadata.divider === 1 ? "100 MS/s" : "12.5 MS/s"} · ` +
        `${samplePeriodNs(capture.metadata.divider)} ns/sample`,
      left,
      9,
    );
  }

  private drawBus(
    capture: ValidatedCapture,
    window: ViewWindow,
    left: number,
    top: number,
    width: number,
    height: number,
  ): void {
    const context = this.context;
    const y = top + 5;
    const busTrackHeight = height - 9;
    const runs = buildBusRuns(capture.samples, window);

    context.fillStyle = "#7990a8";
    context.font = '600 9px "SFMono-Regular", Consolas, monospace';
    context.textAlign = "right";
    context.textBaseline = "middle";
    context.fillText("SW", left - 12, y + busTrackHeight / 2);

    for (const run of runs) {
      const runStartX = sampleBoundaryX(run.start, window, left, width);
      const runEndX = sampleBoundaryX(run.endExclusive, window, left, width);
      const runWidth = Math.max(0, runEndX - runStartX);

      context.fillStyle = "rgba(91, 141, 255, 0.09)";
      context.strokeStyle = "rgba(119, 163, 255, 0.55)";
      context.lineWidth = 1;
      context.beginPath();
      context.moveTo(runStartX, y + busTrackHeight / 2);
      context.lineTo(Math.min(runStartX + 4, runEndX), y);
      context.lineTo(Math.max(runEndX - 4, runStartX), y);
      context.lineTo(runEndX, y + busTrackHeight / 2);
      context.lineTo(Math.max(runEndX - 4, runStartX), y + busTrackHeight);
      context.lineTo(Math.min(runStartX + 4, runEndX), y + busTrackHeight);
      context.closePath();
      context.fill();
      context.stroke();

      if (runWidth >= 26) {
        context.save();
        context.beginPath();
        context.rect(runStartX + 2, y, Math.max(0, runWidth - 4), busTrackHeight);
        context.clip();
        context.fillStyle = "#a9c4f3";
        context.font = '600 8px "SFMono-Regular", Consolas, monospace';
        context.textAlign = "center";
        context.textBaseline = "middle";
        context.fillText(
          formatHex(run.value),
          runStartX + runWidth / 2,
          y + busTrackHeight / 2,
        );
        context.restore();
      }
    }
  }

  private drawTriggerMarker(
    capture: ValidatedCapture,
    window: ViewWindow,
    left: number,
    top: number,
    width: number,
    height: number,
  ): void {
    if (
      capture.metadata.triggerIndex < window.start ||
      capture.metadata.triggerIndex > window.endExclusive
    ) {
      return;
    }

    const context = this.context;
    const x = sampleBoundaryX(
      capture.metadata.triggerIndex,
      window,
      left,
      width,
    );
    const crispX = Math.round(x) + 0.5;

    context.strokeStyle = "#ffbe5c";
    context.lineWidth = 1;
    context.setLineDash([5, 4]);
    context.beginPath();
    context.moveTo(crispX, top - 2);
    context.lineTo(crispX, top + height);
    context.stroke();
    context.setLineDash([]);

    const labelWidth = 92;
    const labelX = Math.max(
      left,
      Math.min(crispX - labelWidth / 2, left + width - labelWidth),
    );
    context.fillStyle = "#ffbe5c";
    context.fillRect(labelX, top - 23, labelWidth, 17);
    context.fillStyle = "#281700";
    context.font = '700 8px "SFMono-Regular", Consolas, monospace';
    context.textAlign = "center";
    context.textBaseline = "middle";
    context.fillText("TRIGGER · 512 · t=0", labelX + labelWidth / 2, top - 14.5);
  }

  private drawTimeAxis(
    capture: ValidatedCapture,
    window: ViewWindow,
    left: number,
    top: number,
    width: number,
  ): void {
    const context = this.context;
    const divisions = 8;
    const periodNs = samplePeriodNs(capture.metadata.divider);

    context.strokeStyle = "rgba(131, 164, 197, 0.22)";
    context.lineWidth = 1;
    context.beginPath();
    context.moveTo(left, top + 3.5);
    context.lineTo(left + width, top + 3.5);
    context.stroke();

    context.fillStyle = "#6f879e";
    context.font = '500 8px "SFMono-Regular", Consolas, monospace';
    context.textBaseline = "top";

    for (let division = 0; division <= divisions; division += 1) {
      const sample =
        window.start +
        ((window.endExclusive - window.start) * division) / divisions;
      const x = sampleBoundaryX(sample, window, left, width);
      context.beginPath();
      context.moveTo(Math.round(x) + 0.5, top + 1);
      context.lineTo(Math.round(x) + 0.5, top + 7);
      context.stroke();

      context.textAlign =
        division === 0 ? "left" : division === divisions ? "right" : "center";
      context.fillText(
        formatTime(
          sampleTimeNs(sample, capture.metadata.triggerIndex, periodNs),
        ),
        x,
        top + 10,
      );
    }
  }

  private drawEmptyGrid(width: number, height: number): void {
    const context = this.context;
    context.strokeStyle = "rgba(131, 164, 197, 0.08)";
    context.lineWidth = 1;
    context.setLineDash([2, 6]);

    for (let division = 1; division < 8; division += 1) {
      const x = (width * division) / 8;
      context.beginPath();
      context.moveTo(Math.round(x) + 0.5, 0);
      context.lineTo(Math.round(x) + 0.5, height);
      context.stroke();
    }
    context.setLineDash([]);
  }
}
