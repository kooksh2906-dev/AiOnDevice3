import type {
  CaptureValidation,
  CheckResult,
  ValidatedCapture,
} from "../app/captureModel";

const VALIDATION_ITEMS: ReadonlyArray<
  readonly [keyof CaptureValidation, string]
> = [
  ["frameCrc", "Frame CRC-16"],
  ["sampleFnv", "Sample FNV-1a"],
  ["length", "Capture length"],
  ["sequence", "DATA sequence"],
  ["freeze", "BRAM freeze"],
];

function validationRow(name: string, result: CheckResult): HTMLElement {
  const row = document.createElement("div");
  row.className = "validation-row";

  const icon = document.createElement("span");
  icon.className = result.pass
    ? "validation-icon"
    : "validation-icon validation-icon--fail";
  icon.textContent = result.pass ? "✓" : "×";
  icon.setAttribute("aria-label", result.pass ? "통과" : "실패");

  const label = document.createElement("span");
  label.className = "validation-name";
  label.textContent = name;

  const detail = document.createElement("span");
  detail.className = result.pass
    ? "validation-value"
    : "validation-value validation-value--fail";
  detail.textContent = result.detail;

  row.append(icon, label, detail);
  return row;
}

export class ValidationPanel {
  public constructor(private readonly root: HTMLElement) {
    this.render(null);
  }

  public render(capture: ValidatedCapture | null): void {
    this.root.replaceChildren();

    if (capture === null) {
      const empty = document.createElement("div");
      empty.className = "empty-card";
      empty.textContent =
        "완전한 Capture만 이 카드와 파형에 원자적으로 반영됩니다.";
      this.root.append(empty);
      return;
    }

    const content = document.createElement("div");
    content.className = "validation-content";
    const list = document.createElement("div");
    list.className = "validation-list";

    for (const [key, name] of VALIDATION_ITEMS) {
      list.append(validationRow(name, capture.validation[key]));
    }

    const allPassed = VALIDATION_ITEMS.every(
      ([key]) => capture.validation[key].pass,
    );
    const banner = document.createElement("div");
    banner.className = allPassed
      ? "validation-banner"
      : "validation-banner validation-banner--fail";
    const status = document.createElement("span");
    status.textContent = allPassed ? "DISPLAY SAFE" : "REJECTED";
    const transaction = document.createElement("span");
    transaction.textContent = `TXN ${capture.metadata.transactionId}`;
    banner.append(status, transaction);

    content.append(list, banner);
    this.root.append(content);
  }
}
