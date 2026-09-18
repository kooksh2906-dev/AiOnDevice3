import type { DashboardEvent } from "../transport/transport";

const MAX_ENTRIES = 200;

interface RawEntry {
  readonly direction: "rx" | "tx" | "system";
  readonly text: string;
  readonly timestamp: number;
}

export class RawLog {
  private readonly entries: RawEntry[] = [];

  public constructor(
    private readonly list: HTMLOListElement,
    private readonly count: HTMLElement,
  ) {}

  public accept(event: DashboardEvent): void {
    if (event.type !== "raw") {
      return;
    }

    this.entries.push({
      direction: event.direction,
      text: event.text,
      timestamp: event.timestamp,
    });
    if (this.entries.length > MAX_ENTRIES) {
      this.entries.splice(0, this.entries.length - MAX_ENTRIES);
    }
    this.render();
  }

  public clear(): void {
    this.entries.splice(0, this.entries.length);
    this.render();
  }

  private render(): void {
    const fragment = document.createDocumentFragment();

    for (const entry of this.entries) {
      const item = document.createElement("li");
      const time = document.createElement("time");
      time.dateTime = new Date(entry.timestamp).toISOString();
      time.textContent = new Date(entry.timestamp).toLocaleTimeString("ko-KR", {
        hour12: false,
        hour: "2-digit",
        minute: "2-digit",
        second: "2-digit",
      });

      const direction = document.createElement("span");
      direction.className =
        entry.direction === "tx"
          ? "raw-direction raw-direction--tx"
          : "raw-direction";
      direction.textContent =
        entry.direction === "system"
          ? "SYS"
          : entry.direction === "tx"
            ? "TX"
            : "RX";

      const content = document.createElement("code");
      content.textContent = entry.text;
      item.append(time, direction, content);
      fragment.append(item);
    }

    this.list.replaceChildren(fragment);
    this.count.textContent = String(this.entries.length);
    this.list.scrollTop = this.list.scrollHeight;
  }
}
