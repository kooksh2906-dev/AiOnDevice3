import {
  DEMO_SPECS,
  formatHex,
  samplePeriodNs,
  type ValidatedCapture,
} from "../app/captureModel";

function metric(label: string, value: string, wide = false): HTMLElement {
  const wrapper = document.createElement("div");
  wrapper.className = wide ? "metric metric--wide" : "metric";

  const name = document.createElement("span");
  name.textContent = label;
  const content = document.createElement("strong");
  content.textContent = value;
  wrapper.append(name, content);
  return wrapper;
}

export class DemoPanel {
  public constructor(private readonly root: HTMLElement) {
    this.render(null);
  }

  public render(capture: ValidatedCapture | null): void {
    this.root.replaceChildren();

    if (capture === null) {
      const empty = document.createElement("div");
      empty.className = "empty-card";
      empty.textContent =
        "검증된 META와 1,024 Sample이 도착하면 Divider, Trigger 조건, " +
        "Circular 주소와 Count를 표시합니다.";
      this.root.append(empty);
      return;
    }

    const { metadata, samples } = capture;
    const spec = DEMO_SPECS[metadata.demo];
    const content = document.createElement("div");
    content.className = "metadata-content";
    const grid = document.createElement("div");
    grid.className = "metadata-grid";

    const triggerBefore = samples[metadata.triggerIndex - 1] ?? 0;
    const triggerSample = samples[metadata.triggerIndex] ?? 0;
    const triggerLabel =
      metadata.mode === "PATTERN"
        ? `(SW & ${formatHex(metadata.patternMask)}) == ` +
          `${formatHex(metadata.patternValue & metadata.patternMask)}`
        : `CH${metadata.channel ?? "?"} ` +
          `${metadata.mode === "RISING" ? "0 → 1" : "1 → 0"}`;
    const condition =
      `${triggerLabel} · ${formatHex(triggerBefore)} → ` +
      formatHex(triggerSample);

    grid.append(
      metric("Demo", `${spec.protocolId}/3 · ${spec.title}`, true),
      metric("Trigger", condition, true),
      metric("Divider", `÷${metadata.divider}`),
      metric("Sample time", `${samplePeriodNs(metadata.divider)} ns`),
      metric("Start addr", `0x${formatHex(metadata.startAddress, 3)}`),
      metric("Trigger addr", `0x${formatHex(metadata.triggerAddress, 3)}`),
      metric("Write addr", `0x${formatHex(metadata.writeAddress, 3)}`),
      metric("Status", `0x${formatHex(metadata.status, 2)}`),
      metric(
        "Trigger count",
        `${metadata.triggerCountBefore} → ${metadata.triggerCountAfter}`,
      ),
      metric(
        "Raw PASS_BITS",
        metadata.passBits === null
          ? "Protocol C에서 매핑"
          : `0x${formatHex(metadata.passBits, 8)}`,
      ),
    );

    content.append(grid);
    this.root.append(content);
  }
}
