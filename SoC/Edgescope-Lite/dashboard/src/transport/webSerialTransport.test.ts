import { describe, expect, it } from "vitest";

import {
  WebSerialTransport,
  type SerialOpenOptions,
  type SerialPortLike,
  type WebSerialEnvironment,
} from "./webSerialTransport";
import type { DashboardEvent } from "./transport";

class FakeSerialPort implements SerialPortLike {
  public readonly writes: number[][] = [];
  public readonly lifecycle: string[] = [];
  public openOptions: SerialOpenOptions | null = null;
  public controller: ReadableStreamDefaultController<Uint8Array> | null = null;

  public constructor(
    private readonly openGate: Promise<void> | null = null,
    private readonly closeGate: Promise<void> | null = null,
  ) {}

  public readonly readable = new ReadableStream<Uint8Array>({
    start: (controller) => {
      this.controller = controller;
    },
    cancel: () => {
      this.lifecycle.push("reader.cancel");
    },
  });

  public readonly writable = new WritableStream<Uint8Array>({
    write: (chunk) => {
      this.writes.push([...chunk]);
    },
  });

  public async open(options: SerialOpenOptions): Promise<void> {
    this.openOptions = options;
    this.lifecycle.push("port.open");
    await this.openGate;
  }

  public async close(): Promise<void> {
    this.lifecycle.push("port.close");
    await this.closeGate;
  }
}

function environmentFor(ports: readonly FakeSerialPort[]): WebSerialEnvironment {
  let index = 0;
  return {
    secureContext: true,
    now: () => 100,
    serial: {
      requestPort: async () => {
        const port = ports[index];
        index += 1;
        if (port === undefined) {
          throw new Error("No fake port");
        }
        return port;
      },
    },
  };
}

function deferred<T>(): {
  readonly promise: Promise<T>;
  readonly resolve: (value: T) => void;
} {
  let resolvePromise!: (value: T | PromiseLike<T>) => void;
  const promise = new Promise<T>((resolve) => {
    resolvePromise = resolve;
  });
  return {
    promise,
    resolve: (value) => resolvePromise(value),
  };
}

describe("WebSerialTransport", () => {
  it("opens 9600 8N1 and writes exact one-byte commands", async () => {
    const port = new FakeSerialPort();
    const transport = new WebSerialTransport(environmentFor([port]));

    await transport.connect();
    await transport.sendCommand("s");
    await transport.sendCommand("f");
    await transport.sendCommand("?");

    expect(port.openOptions).toEqual({
      baudRate: 9600,
      dataBits: 8,
      stopBits: 1,
      parity: "none",
      flowControl: "none",
    });
    expect(port.writes).toEqual([[0x3f], [0x73], [0x66], [0x3f]]);
    await transport.disconnect();
    expect(port.lifecycle).toEqual([
      "port.open",
      "reader.cancel",
      "port.close",
    ]);
  });

  it("starts the reader and emits a stable copy of received bytes", async () => {
    const port = new FakeSerialPort();
    const transport = new WebSerialTransport(environmentFor([port]));
    const events: DashboardEvent[] = [];
    transport.subscribe((event) => events.push(event));

    await transport.connect();
    port.controller?.enqueue(Uint8Array.of(0x40, 0x45, 0x53, 0x4c));
    await Promise.resolve();
    await Promise.resolve();

    const bytesEvent = events.find((event) => event.type === "bytes");
    expect(bytesEvent?.type === "bytes" ? [...bytesEvent.data] : []).toEqual([
      0x40, 0x45, 0x53, 0x4c,
    ]);
    await transport.disconnect();
  });

  it("automatically requests state after initial connect and reconnect", async () => {
    const first = new FakeSerialPort();
    const second = new FakeSerialPort();
    const transport = new WebSerialTransport(environmentFor([first, second]));

    await transport.connect();
    expect(first.writes).toEqual([[0x3f]]);
    await transport.disconnect();
    await transport.connect();
    expect(second.writes).toEqual([[0x3f]]);
    await transport.disconnect();
  });

  it("shares an in-flight disconnect until the port is actually closed", async () => {
    const closeGate = deferred<void>();
    const port = new FakeSerialPort(null, closeGate.promise);
    const transport = new WebSerialTransport(environmentFor([port]));

    await transport.connect();
    const firstDisconnect = transport.disconnect();
    const secondDisconnect = transport.disconnect();

    expect(secondDisconnect).toBe(firstDisconnect);
    for (let attempt = 0; attempt < 10; attempt += 1) {
      if (port.lifecycle.includes("port.close")) {
        break;
      }
      await Promise.resolve();
    }
    expect(port.lifecycle).toContain("port.close");

    let completed = false;
    void secondDisconnect.then(() => {
      completed = true;
    });
    await Promise.resolve();
    expect(completed).toBe(false);

    closeGate.resolve(undefined);
    await firstDisconnect;
    expect(completed).toBe(true);
    expect(transport.connectionState).toBe("disconnected");
  });

  it("reports an insecure context without requesting a port", async () => {
    let requested = false;
    const transport = new WebSerialTransport({
      secureContext: false,
      now: Date.now,
      serial: {
        requestPort: async () => {
          requested = true;
          return new FakeSerialPort();
        },
      },
    });

    await expect(transport.connect()).rejects.toThrow("Secure Context");
    expect(requested).toBe(false);
    expect(transport.connectionState).toBe("unsupported");
  });

  it("cancels a port request that resolves after disconnect", async () => {
    const request = deferred<SerialPortLike>();
    const port = new FakeSerialPort();
    const transport = new WebSerialTransport({
      secureContext: true,
      now: Date.now,
      serial: { requestPort: () => request.promise },
    });

    const connecting = transport.connect();
    await Promise.resolve();
    await transport.disconnect();
    request.resolve(port);

    await expect(connecting).rejects.toThrow("session changed");
    expect(port.openOptions).toBeNull();
    expect(transport.connectionState).toBe("disconnected");
  });

  it("closes a port that finishes opening after its session is cancelled", async () => {
    const openGate = deferred<void>();
    const port = new FakeSerialPort(openGate.promise);
    const transport = new WebSerialTransport(environmentFor([port]));

    const connecting = transport.connect();
    await Promise.resolve();
    await Promise.resolve();
    await transport.disconnect();
    openGate.resolve(undefined);

    await expect(connecting).rejects.toThrow("session changed");
    expect(port.lifecycle).toEqual(["port.open", "port.close"]);
    expect(transport.connectionState).toBe("disconnected");
  });

  it("turns an unexpected receive EOF into a closed error session", async () => {
    const port = new FakeSerialPort();
    const transport = new WebSerialTransport(environmentFor([port]));

    await transport.connect();
    port.controller?.close();
    for (let attempt = 0; attempt < 10; attempt += 1) {
      if (transport.connectionState === "error") {
        break;
      }
      await Promise.resolve();
    }

    expect(transport.connectionState).toBe("error");
    expect(port.lifecycle).toEqual(["port.open", "port.close"]);
    await transport.disconnect();
    expect(transport.connectionState).toBe("disconnected");
  });
});
