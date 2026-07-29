import {
  EventTransport,
  type ConnectionState,
  type ControlCommand,
} from "./transport";

export interface SerialOpenOptions {
  readonly baudRate: number;
  readonly dataBits: 7 | 8;
  readonly stopBits: 1 | 2;
  readonly parity: "none" | "even" | "odd";
  readonly flowControl: "none" | "hardware";
}

export interface SerialPortLike {
  readonly readable: ReadableStream<Uint8Array> | null;
  readonly writable: WritableStream<Uint8Array> | null;
  open(options: SerialOpenOptions): Promise<void>;
  close(): Promise<void>;
}

export interface SerialApiLike {
  requestPort(): Promise<SerialPortLike>;
}

export interface WebSerialEnvironment {
  readonly serial: SerialApiLike | null;
  readonly secureContext: boolean;
  readonly now: () => number;
}

function browserEnvironment(): WebSerialEnvironment {
  const browserNavigator = globalThis.navigator as
    | (Navigator & { serial?: SerialApiLike })
    | undefined;

  return {
    serial: browserNavigator?.serial ?? null,
    secureContext: globalThis.isSecureContext === true,
    now: Date.now,
  };
}

function commandByte(command: ControlCommand): Uint8Array {
  return Uint8Array.of(command.charCodeAt(0));
}

function visibleChunk(chunk: Uint8Array): string {
  const decoded = new TextDecoder().decode(chunk);
  const visible = decoded.replaceAll("\r", "\\r").replaceAll("\n", "\\n");
  return visible.length <= 512 ? visible : `${visible.slice(0, 512)}…`;
}

class SerialSessionCancelledError extends Error {
  public constructor() {
    super("Serial session changed while an operation was pending.");
    this.name = "SerialSessionCancelledError";
  }
}

export class WebSerialTransport extends EventTransport {
  public readonly kind = "serial" as const;

  private stateValue: ConnectionState = "disconnected";
  private readonly environment: WebSerialEnvironment;
  private port: SerialPortLike | null = null;
  private reader: ReadableStreamDefaultReader<Uint8Array> | null = null;
  private readLoopPromise: Promise<void> | null = null;
  private disconnectRequested = false;
  private hasOpenedBefore = false;
  private writeQueue: Promise<void> = Promise.resolve();
  private sessionGeneration = 0;
  private disconnectPromise: Promise<void> | null = null;

  public constructor(environment: WebSerialEnvironment = browserEnvironment()) {
    super();
    this.environment = environment;
  }

  public get connectionState(): ConnectionState {
    return this.stateValue;
  }

  public get supported(): boolean {
    return this.environment.secureContext && this.environment.serial !== null;
  }

  public async connect(): Promise<void> {
    if (this.disconnectPromise !== null) {
      await this.disconnectPromise;
    }

    if (this.stateValue === "connected" || this.stateValue === "connecting") {
      return;
    }

    if (!this.environment.secureContext) {
      const message =
        "Web Serial은 HTTPS 또는 localhost Secure Context에서만 사용할 수 있습니다.";
      this.setConnection("unsupported", message);
      throw new Error(message);
    }

    if (this.environment.serial === null) {
      const message =
        "이 브라우저는 Web Serial을 지원하지 않습니다. 데스크톱 Chrome을 사용하세요.";
      this.setConnection("unsupported", message);
      throw new Error(message);
    }

    const generation = this.sessionGeneration + 1;
    this.sessionGeneration = generation;
    this.disconnectRequested = false;
    this.setConnection("connecting", "Serial Port 선택 대기 중");
    let selectedPort: SerialPortLike | null = null;
    let selectedPortOpened = false;

    try {
      // requestPort() stays directly on the user-click call path in main.ts.
      selectedPort = await this.environment.serial.requestPort();
      this.assertSession(generation);
      await selectedPort.open({
        baudRate: 9600,
        dataBits: 8,
        stopBits: 1,
        parity: "none",
        flowControl: "none",
      });
      selectedPortOpened = true;
      this.assertSession(generation);

      if (selectedPort.readable === null || selectedPort.writable === null) {
        await selectedPort.close();
        selectedPortOpened = false;
        throw new Error("선택한 Serial Port에서 읽기/쓰기를 시작할 수 없습니다.");
      }

      this.port = selectedPort;
      this.reader = selectedPort.readable.getReader();
      this.readLoopPromise = this.readLoop(
        this.reader,
        selectedPort,
        generation,
      );
      this.setConnection("connected", "Web Serial 연결됨 · 9,600 8N1");
      this.emitRaw("system", "[serial] port opened at 9600 baud, 8N1");

      await this.sendCommand("?");
      this.emitRaw(
        "system",
        this.hasOpenedBefore
          ? "[serial] reconnect resync requested"
          : "[serial] initial state sync requested",
      );
      this.hasOpenedBefore = true;
    } catch (error) {
      if (
        error instanceof SerialSessionCancelledError ||
        generation !== this.sessionGeneration
      ) {
        if (
          selectedPortOpened &&
          selectedPort !== null &&
          selectedPort !== this.port
        ) {
          await this.closeDetachedPort(selectedPort);
        }
        throw error instanceof SerialSessionCancelledError
          ? error
          : new SerialSessionCancelledError();
      }

      const message = this.errorMessage(error, "Serial Port 연결에 실패했습니다.");
      await this.closePortAfterFailure();
      this.setConnection("error", message);
      this.emit({ type: "error", message, recoverable: true });
      throw error;
    }
  }

  public disconnect(): Promise<void> {
    if (this.disconnectPromise !== null) {
      return this.disconnectPromise;
    }
    if (this.stateValue === "disconnected") {
      return Promise.resolve();
    }

    let resolveDisconnect!: () => void;
    let rejectDisconnect!: (reason: unknown) => void;
    const sharedPromise = new Promise<void>((resolve, reject) => {
      resolveDisconnect = resolve;
      rejectDisconnect = reject;
    });
    this.disconnectPromise = sharedPromise;

    void this.performDisconnect().then(resolveDisconnect, rejectDisconnect);
    void sharedPromise.then(
      () => {
        if (this.disconnectPromise === sharedPromise) {
          this.disconnectPromise = null;
        }
      },
      () => {
        if (this.disconnectPromise === sharedPromise) {
          this.disconnectPromise = null;
        }
      },
    );
    return sharedPromise;
  }

  private async performDisconnect(): Promise<void> {
    this.sessionGeneration += 1;
    this.disconnectRequested = true;
    this.setConnection("disconnecting", "Serial Port 연결 해제 중");

    const reader = this.reader;
    if (reader !== null) {
      try {
        await reader.cancel();
      } catch {
        // A physical USB disconnect can make cancel reject; cleanup continues.
      }
    }

    if (this.readLoopPromise !== null) {
      try {
        await this.readLoopPromise;
      } catch {
        // The read loop already emitted a useful error.
      }
    }

    try {
      await this.writeQueue;
    } catch {
      // A failed queued write must not prevent the port from closing.
    }

    const port = this.port;
    this.reader = null;
    this.readLoopPromise = null;
    this.writeQueue = Promise.resolve();

    if (port !== null) {
      try {
        await port.close();
      } catch (error) {
        const message = this.errorMessage(
          error,
          "Serial Port를 완전히 닫지 못했습니다.",
        );
        this.emit({ type: "error", message, recoverable: true });
        this.setConnection("error", message);
        return;
      }
    }

    this.port = null;
    this.setConnection("disconnected", "연결 안 됨");
    this.emitRaw(
      "system",
      "[serial] disconnected; incomplete capture discarded by protocol bridge",
    );
  }

  public sendCommand(command: ControlCommand): Promise<void> {
    const port = this.port;
    const generation = this.sessionGeneration;
    if (
      this.stateValue !== "connected" ||
      port === null ||
      port.writable === null
    ) {
      const message = "연결된 Serial Port가 없어 명령을 보낼 수 없습니다.";
      this.emit({ type: "error", message, recoverable: true });
      return Promise.reject(new Error(message));
    }

    const bytes = commandByte(command);
    const operation = this.writeQueue.then(async () => {
      this.assertPortSession(generation, port);
      const writable = port.writable;
      if (writable === null || writable === undefined) {
        throw new Error("Serial writer가 연결 중 사라졌습니다.");
      }

      const writer = writable.getWriter();
      try {
        await writer.write(bytes);
        this.assertPortSession(generation, port);
        this.emitRaw("tx", command);
      } finally {
        writer.releaseLock();
      }
    });

    this.writeQueue = operation.catch(() => undefined);
    return operation.catch((error: unknown) => {
      if (error instanceof SerialSessionCancelledError) {
        throw error;
      }
      const message = this.errorMessage(error, `명령 '${command}' 전송 실패`);
      this.emit({ type: "error", message, recoverable: true });
      throw error;
    });
  }

  private async readLoop(
    reader: ReadableStreamDefaultReader<Uint8Array>,
    port: SerialPortLike,
    generation: number,
  ): Promise<void> {
    let unexpectedMessage: string | null = null;

    try {
      while (
        !this.disconnectRequested &&
        generation === this.sessionGeneration
      ) {
        const { value, done } = await reader.read();
        if (generation !== this.sessionGeneration) {
          break;
        }
        if (done) {
          if (
            !this.disconnectRequested &&
            generation === this.sessionGeneration
          ) {
            unexpectedMessage = "Serial Port 수신 Stream이 종료되었습니다.";
          }
          break;
        }
        if (value !== undefined && value.byteLength > 0) {
          const stableCopy = value.slice();
          this.emit({ type: "bytes", data: stableCopy });
          this.emitRaw("rx", visibleChunk(stableCopy));
        }
      }
    } catch (error) {
      if (
        !this.disconnectRequested &&
        generation === this.sessionGeneration
      ) {
        unexpectedMessage = this.errorMessage(
          error,
          "Serial 수신이 예기치 않게 중단되었습니다.",
        );
      }
    } finally {
      try {
        reader.releaseLock();
      } catch {
        // releaseLock is idempotent enough for close-race cleanup purposes.
      }
      if (this.reader === reader && generation === this.sessionGeneration) {
        this.reader = null;
      }

      if (
        unexpectedMessage !== null &&
        generation === this.sessionGeneration
      ) {
        this.sessionGeneration += 1;
        this.disconnectRequested = true;
        try {
          await this.writeQueue;
        } catch {
          // The receive incident remains primary; queued writes are invalidated.
        }

        let closeMessage = "";
        try {
          await port.close();
          if (this.port === port) {
            this.port = null;
          }
        } catch (error) {
          closeMessage =
            " " +
            this.errorMessage(
              error,
              "Serial Port cleanup도 완료되지 않았습니다.",
            );
        }
        this.readLoopPromise = null;
        this.writeQueue = Promise.resolve();
        const message = `${unexpectedMessage}${closeMessage}`;
        this.setConnection("error", message);
        this.emit({
          type: "error",
          message,
          recoverable: true,
        });
      }
    }
  }

  private async closePortAfterFailure(): Promise<void> {
    this.sessionGeneration += 1;
    this.disconnectRequested = true;

    if (this.reader !== null) {
      try {
        await this.reader.cancel();
      } catch {
        // Continue best-effort cleanup.
      }
    }
    if (this.readLoopPromise !== null) {
      try {
        await this.readLoopPromise;
      } catch {
        // Continue best-effort cleanup.
      }
    }
    try {
      await this.writeQueue;
    } catch {
      // Continue best-effort cleanup.
    }

    const port = this.port;
    this.reader = null;
    this.readLoopPromise = null;
    this.writeQueue = Promise.resolve();
    if (port !== null) {
      try {
        await port.close();
        if (this.port === port) {
          this.port = null;
        }
      } catch {
        // The original connection error is more useful to the caller.
      }
    }
  }

  private assertSession(generation: number): void {
    if (
      generation !== this.sessionGeneration ||
      this.disconnectRequested
    ) {
      throw new SerialSessionCancelledError();
    }
  }

  private assertPortSession(
    generation: number,
    port: SerialPortLike,
  ): void {
    this.assertSession(generation);
    if (this.port !== port || this.stateValue !== "connected") {
      throw new SerialSessionCancelledError();
    }
  }

  private async closeDetachedPort(port: SerialPortLike): Promise<void> {
    try {
      await port.close();
    } catch {
      // The detached session must not mutate the active transport state.
    }
  }

  private setConnection(state: ConnectionState, message: string): void {
    this.stateValue = state;
    this.emit({
      type: "transport",
      status: { state, message },
    });
  }

  private emitRaw(
    direction: "rx" | "tx" | "system",
    text: string,
  ): void {
    this.emit({
      type: "raw",
      direction,
      text,
      timestamp: this.environment.now(),
    });
  }

  private errorMessage(error: unknown, fallback: string): string {
    return error instanceof Error && error.message.length > 0
      ? error.message
      : fallback;
  }
}
