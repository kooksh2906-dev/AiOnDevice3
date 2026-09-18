import { describe, expect, it } from "vitest";

import { MockTransport } from "./mockTransport";
import type { DashboardEvent } from "./transport";

describe("MockTransport", () => {
  it("replays the successful firmware workflow and emits only after f", async () => {
    const transport = new MockTransport({ delayMs: 0, now: () => 1234 });
    const events: DashboardEvent[] = [];
    transport.subscribe((event) => events.push(event));

    await transport.connect();
    await transport.sendCommand("s");
    expect(events.some((event) => event.type === "capture")).toBe(false);
    expect(
      events.some(
        (event) =>
          event.type === "workflow" && event.workflow.state === "WAIT_FREEZE",
      ),
    ).toBe(true);

    await transport.sendCommand("f");
    expect(events.filter((event) => event.type === "capture")).toHaveLength(1);
    const lastEvent = events
      .filter((event) => event.type === "workflow")
      .at(-1);
    expect(
      lastEvent?.type === "workflow" &&
        lastEvent.workflow.state === "WAIT_START",
    ).toBe(true);
  });

  it("models timeout as retry without publishing a capture", async () => {
    const transport = new MockTransport({ delayMs: 0 });
    const events: DashboardEvent[] = [];
    transport.setScenario("timeout");
    transport.subscribe((event) => events.push(event));

    await transport.connect();
    await transport.sendCommand("s");

    expect(events.some((event) => event.type === "capture")).toBe(false);
    expect(
      events.some(
        (event) =>
          event.type === "workflow" && event.workflow.state === "TIMEOUT",
      ),
    ).toBe(true);
    const lastWorkflow = events
      .filter((event) => event.type === "workflow")
      .at(-1);
    expect(
      lastWorkflow?.type === "workflow" &&
        lastWorkflow.workflow.state === "WAIT_START" &&
        lastWorkflow.workflow.attempt === 2,
    ).toBe(true);
  });

  it("emits a rejection instead of corrupt capture data", async () => {
    const transport = new MockTransport({ delayMs: 0 });
    const events: DashboardEvent[] = [];
    transport.setScenario("corrupt");
    transport.subscribe((event) => events.push(event));

    await transport.connect();
    await transport.sendCommand("s");
    await transport.sendCommand("f");

    expect(events.some((event) => event.type === "capture")).toBe(false);
    expect(events.some((event) => event.type === "capture-rejected")).toBe(true);
  });

  it("sends semantic resync after reconnect", async () => {
    const transport = new MockTransport({ delayMs: 0 });
    const events: DashboardEvent[] = [];
    transport.subscribe((event) => events.push(event));

    await transport.connect();
    await transport.disconnect();
    await transport.connect();

    const resyncWrites = events.filter(
      (event) =>
        event.type === "raw" &&
        event.direction === "tx" &&
        event.text === "?",
    );
    expect(resyncWrites).toHaveLength(1);
  });

  it("cancels an in-flight playback and returns to WAIT_START on reconnect", async () => {
    const transport = new MockTransport({ delayMs: 5 });
    const events: DashboardEvent[] = [];
    transport.subscribe((event) => events.push(event));

    await transport.connect();
    const playback = transport.sendCommand("s");
    const playbackResult = playback.catch((error: unknown) => error);
    await new Promise<void>((resolve) => {
      globalThis.setTimeout(resolve, 7);
    });
    await transport.disconnect();
    const playbackError = await playbackResult;
    expect(playbackError).toBeInstanceOf(Error);
    expect((playbackError as Error).message).toContain("session changed");
    await transport.connect();

    const lastWorkflow = events
      .filter((event) => event.type === "workflow")
      .at(-1);
    expect(
      lastWorkflow?.type === "workflow" &&
        lastWorkflow.workflow.state === "WAIT_START" &&
        lastWorkflow.workflow.code === "MOCK_SESSION_RESET",
    ).toBe(true);
    expect(events.some((event) => event.type === "capture")).toBe(false);
  });
});
